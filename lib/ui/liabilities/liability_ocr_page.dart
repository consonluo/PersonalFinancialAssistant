import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/ai_service.dart';
import '../../core/utils/format_utils.dart';
import '../../providers/database_provider.dart';
import '../../providers/family_provider.dart';
import '../../providers/sync_provider.dart';
import '../../data/database/app_database.dart';

/// 负债截图识别页面
class LiabilityOcrPage extends ConsumerStatefulWidget {
  final String? memberId;
  const LiabilityOcrPage({super.key, this.memberId});

  @override
  ConsumerState<LiabilityOcrPage> createState() => _LiabilityOcrPageState();
}

class _LiabilityOcrPageState extends ConsumerState<LiabilityOcrPage> {
  final _picker = ImagePicker();
  Uint8List? _imageBytes;
  bool _isRecognizing = false;
  String _streamContent = '';
  List<Map<String, dynamic>>? _results;
  String? _selectedMemberId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedMemberId = widget.memberId;
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(familyMembersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('截图导入负债')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          membersAsync.when(
            data: (members) => DropdownButtonFormField<String>(
              value: _selectedMemberId,
              decoration: const InputDecoration(labelText: '所属成员'),
              items: members.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))).toList(),
              onChanged: (v) => setState(() => _selectedMemberId = v),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox(),
          ),
          const SizedBox(height: 16),

          if (_imageBytes == null)
            InkWell(
              onTap: _pickImage,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: AppColors.backgroundCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.textHint.withValues(alpha: 0.3)),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined, size: 48, color: AppColors.textHint),
                    SizedBox(height: 8),
                    Text('点击选择贷款/负债截图', style: TextStyle(color: AppColors.textHint)),
                    SizedBox(height: 4),
                    Text('支持房贷、车贷、信用卡等截图', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
                  ],
                ),
              ),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_imageBytes!, height: 200, fit: BoxFit.cover),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _pickImage, child: const Text('重新选择'))),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isRecognizing ? null : _recognize,
                    child: _isRecognizing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('AI 识别'),
                  ),
                ),
              ],
            ),
          ],

          if (_streamContent.isNotEmpty || _isRecognizing) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('AI 识别中', style: TextStyle(fontWeight: FontWeight.w600)),
                        if (_isRecognizing) ...[
                          const SizedBox(width: 8),
                          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_streamContent, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                  ],
                ),
              ),
            ),
          ],

          if (_results != null) ...[
            const SizedBox(height: 16),
            Text('识别到 ${_results!.length} 笔负债', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 8),
            ..._results!.map((l) {
              final typeLabel = LiabilityType.values.firstWhere(
                (t) => t.name == l['type'], orElse: () => LiabilityType.other).label;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.money_off, color: AppColors.error),
                  title: Text(l['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('$typeLabel · 剩余${FormatUtils.formatCurrency((l['remainingAmount'] as num?)?.toDouble() ?? 0)} · 月供${FormatUtils.formatCurrency((l['monthlyPayment'] as num?)?.toDouble() ?? 0)}'),
                ),
              );
            }),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedMemberId == null ? null : _saveAll,
                child: const Text('确认保存全部'),
              ),
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: AppColors.error)),
          ],
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 2048);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() { _imageBytes = bytes; _results = null; _error = null; _streamContent = ''; });
    }
  }

  Future<void> _recognize() async {
    if (_imageBytes == null) return;
    setState(() { _isRecognizing = true; _error = null; _streamContent = ''; _results = null; });

    try {
      final base64Image = base64Encode(_imageBytes!);
      final prompt = '''你是金融负债信息识别专家。请从截图中提取所有贷款/负债信息。

提取规则：
1. 提取每笔负债的：名称(name)、类型(type)、总金额(totalAmount)、剩余金额(remainingAmount)、年化利率(interestRate)、月还款额(monthlyPayment)
2. type 必须是：mortgage(商业房贷)/housingFund(公积金房贷)/combinedLoan(组合贷)/carLoan(车贷)/renovationLoan(装修贷)/consumerLoan(消费贷)/creditCard(信用卡)/installment(分期付款)/businessLoan(经营贷)/personalLoan(亲友借款)/loan(其他借款)/other(其他)
3. 利率为年化百分比数字（如 4.2 表示 4.2%）
4. 缺失字段填 0

返回严格JSON数组（不要markdown）：
[{"name": "招商银行房贷", "type": "mortgage", "totalAmount": 2000000, "remainingAmount": 1500000, "interestRate": 4.2, "monthlyPayment": 9800}]''';

      final result = await AiService.chat('$prompt\n\n[图片数据: data:image/jpeg;base64,$base64Image]');
      if (!mounted) return;

      setState(() { _streamContent = result; _isRecognizing = false; });

      try {
        final trimmed = result.trim();
        List<dynamic> parsed;
        if (trimmed.startsWith('[')) {
          parsed = jsonDecode(trimmed);
        } else {
          final match = RegExp(r'```(?:json)?\s*\n?([\s\S]*?)\n?```').firstMatch(trimmed);
          parsed = jsonDecode(match?.group(1)?.trim() ?? trimmed);
        }
        setState(() => _results = parsed.cast<Map<String, dynamic>>());
      } catch (_) {
        setState(() => _error = 'AI 返回格式异常，请重试');
      }
    } catch (e) {
      if (mounted) setState(() { _isRecognizing = false; _error = '识别失败: $e'; });
    }
  }

  Future<void> _saveAll() async {
    if (_results == null || _selectedMemberId == null) return;
    final db = ref.read(databaseProvider);
    final now = DateTime.now();

    for (final l in _results!) {
      await db.insertLiability(LiabilitiesCompanion(
        id: Value(const Uuid().v4()),
        memberId: Value(_selectedMemberId!),
        type: Value(l['type'] as String? ?? 'other'),
        name: Value(l['name'] as String? ?? ''),
        totalAmount: Value((l['totalAmount'] as num?)?.toDouble() ?? 0),
        remainingAmount: Value((l['remainingAmount'] as num?)?.toDouble() ?? 0),
        interestRate: Value((l['interestRate'] as num?)?.toDouble() ?? 0),
        monthlyPayment: Value((l['monthlyPayment'] as num?)?.toDouble() ?? 0),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
    }

    ref.read(autoSyncProvider).triggerAutoSync();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导入 ${_results!.length} 笔负债')));
      context.pop();
    }
  }
}
