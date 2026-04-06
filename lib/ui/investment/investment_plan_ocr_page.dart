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
import '../../providers/database_provider.dart';
import '../../providers/account_provider.dart';
import '../../providers/sync_provider.dart';
import '../../data/database/app_database.dart';

/// 定投计划截图识别页面
class InvestmentPlanOcrPage extends ConsumerStatefulWidget {
  const InvestmentPlanOcrPage({super.key});

  @override
  ConsumerState<InvestmentPlanOcrPage> createState() => _InvestmentPlanOcrPageState();
}

class _InvestmentPlanOcrPageState extends ConsumerState<InvestmentPlanOcrPage> {
  final _picker = ImagePicker();
  Uint8List? _imageBytes;
  bool _isRecognizing = false;
  String _streamContent = '';
  List<Map<String, dynamic>>? _results;
  String? _selectedAccountId;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(allAccountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('截图导入定投计划')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 选择账户
          accountsAsync.when(
            data: (accounts) => DropdownButtonFormField<String>(
              value: _selectedAccountId,
              decoration: const InputDecoration(labelText: '关联账户'),
              items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text('${a.name} · ${a.institution}'))).toList(),
              onChanged: (v) => setState(() => _selectedAccountId = v),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox(),
          ),
          const SizedBox(height: 16),

          // 图片选择区
          if (_imageBytes == null)
            InkWell(
              onTap: _pickImage,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: AppColors.backgroundCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.textHint.withValues(alpha: 0.3), style: BorderStyle.solid),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined, size: 48, color: AppColors.textHint),
                    SizedBox(height: 8),
                    Text('点击选择定投计划截图', style: TextStyle(color: AppColors.textHint)),
                    SizedBox(height: 4),
                    Text('支持各基金APP定投页面截图', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
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

          // 流式输出区
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

          // 识别结果
          if (_results != null) ...[
            const SizedBox(height: 16),
            Text('识别到 ${_results!.length} 个定投计划', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 8),
            ..._results!.asMap().entries.map((e) {
              final p = e.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.event_repeat, color: AppColors.primary),
                  title: Text(p['assetName'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${p['assetCode'] ?? ''} · ${p['frequency'] ?? 'monthly'} · ¥${p['amount'] ?? 0}'),
                ),
              );
            }),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedAccountId == null ? null : _saveAll,
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
      final prompt = '''你是金融定投计划识别专家。请从截图中提取所有定投计划信息。

提取规则：
1. 提取每个定投计划的：标的代码(assetCode)、标的名称(assetName)、定投金额(amount)、定投频率(frequency)
2. frequency 必须是：daily(每日)/weekly(每周)/biweekly(每两周)/monthly(每月)
3. 金额为每次定投金额（数字）
4. 如果无法确定代码，填 "unknown"

返回严格JSON数组（不要markdown）：
[{"assetCode": "161725", "assetName": "招商中证白酒", "amount": 500, "frequency": "weekly"}]''';

      final result = await AiService.chat('$prompt\n\n[图片数据: data:image/jpeg;base64,$base64Image]');
      if (!mounted) return;

      setState(() {
        _streamContent = result;
        _isRecognizing = false;
      });

      // 解析
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
    if (_results == null || _selectedAccountId == null) return;
    final db = ref.read(databaseProvider);
    final now = DateTime.now();

    for (final p in _results!) {
      await db.insertInvestmentPlan(InvestmentPlansCompanion(
        id: Value(const Uuid().v4()),
        accountId: Value(_selectedAccountId!),
        assetCode: Value(p['assetCode'] as String? ?? 'unknown'),
        assetName: Value(p['assetName'] as String? ?? ''),
        amount: Value((p['amount'] as num?)?.toDouble() ?? 0),
        frequency: Value(p['frequency'] as String? ?? 'monthly'),
        nextDate: Value(now.add(const Duration(days: 1))),
        isActive: Value(true),
        createdAt: Value(now),
      ));
    }

    ref.read(autoSyncProvider).triggerAutoSync();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导入 ${_results!.length} 个定投计划')));
      context.pop();
    }
  }
}
