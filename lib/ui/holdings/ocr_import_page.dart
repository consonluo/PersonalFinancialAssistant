import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/ocr_service.dart';
import '../../core/utils/ocr_parser.dart';
import '../../core/utils/asset_classifier.dart';
import '../../core/utils/exchange_rate_service.dart';
import '../../providers/database_provider.dart';
import '../../providers/ocr_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/family_provider.dart';
import '../../providers/holding_provider.dart';
import '../../providers/account_provider.dart';
import '../../data/database/app_database.dart';

/// 常用机构列表
const _commonInstitutions = [
  '富途证券', '华泰证券', '中信证券', '中银证券', '国泰君安', '招商证券',
  '东方财富', '同花顺', '雪球', '老虎证券', '长桥证券', '盈透证券',
  '微众银行', '招商银行', '工商银行', '建设银行', '中国银行', '农业银行',
  '天天基金', '蚂蚁财富', '理财通', '京东金融',
];

class OcrImportPage extends ConsumerStatefulWidget {
  final String accountId;
  const OcrImportPage({super.key, required this.accountId});

  @override
  ConsumerState<OcrImportPage> createState() => _OcrImportPageState();
}

class _OcrImportPageState extends ConsumerState<OcrImportPage> {
  final _picker = ImagePicker();
  final _institutionController = TextEditingController();
  List<Uint8List> _selectedImages = [];
  String _selectedInstitution = '';
  String? _selectedMemberId;
  bool _hasAccount = false;
  int _processedCount = 0;
  int _totalImages = 0;

  @override
  void initState() {
    super.initState();
    if (widget.accountId.isNotEmpty) {
      _hasAccount = true;
      _loadAccountInfo();
    }
  }

  /// 从已有账户加载机构名称
  Future<void> _loadAccountInfo() async {
    final db = ref.read(databaseProvider);
    final account = await db.getAccountById(widget.accountId);
    if (account != null && mounted) {
      setState(() {
        _selectedInstitution = account.institution;
        _institutionController.text = account.institution;
      });
    }
  }

  @override
  void dispose() {
    _institutionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ocrState = ref.watch(ocrResultProvider);
    final isDesktopOrWeb = kIsWeb || _isDesktop;
    final membersAsync = ref.watch(familyMembersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('录入持仓'),
        actions: [
          if (ocrState.results.isNotEmpty)
            TextButton(
              onPressed: _confirmImport,
              child: Text('导入(${ocrState.results.length})'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 已有账户时显示机构名称
            if (_hasAccount && _selectedInstitution.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.business, size: 20, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(_selectedInstitution, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 没有 accountId 时才需要选成员和机构
            if (!_hasAccount) ...[
              // Step 1: 选择所属成员
              const Text('所属成员', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              membersAsync.when(
                data: (members) => DropdownButtonFormField<String>(
                  value: _selectedMemberId,
                  decoration: const InputDecoration(hintText: '选择成员', isDense: true),
                  items: members.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))).toList(),
                  onChanged: (v) => setState(() => _selectedMemberId = v),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('加载失败'),
              ),
              const SizedBox(height: 20),

              // Step 2: 选择/输入机构
            const Text('金融机构', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('选择或输入券商/银行名称', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Autocomplete<String>(
              optionsBuilder: (textEditingValue) {
                if (textEditingValue.text.isEmpty) return _commonInstitutions;
                return _commonInstitutions.where((i) =>
                    i.contains(textEditingValue.text));
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                _institutionController.text = controller.text;
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    hintText: '例如：富途证券、微众银行',
                    prefixIcon: Icon(Icons.business, size: 20),
                  ),
                  onChanged: (v) => setState(() => _selectedInstitution = v),
                );
              },
              onSelected: (v) => setState(() {
                _selectedInstitution = v;
                _institutionController.text = v;
              }),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: ['富途证券', '微众银行', '东方财富', '天天基金', '招商银行'].map((inst) {
                final selected = _selectedInstitution == inst;
                return ChoiceChip(
                  label: Text(inst, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppColors.textPrimary)),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    _selectedInstitution = inst;
                    _institutionController.text = inst;
                  }),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
              const SizedBox(height: 24),
            ], // end if (!_hasAccount)

            // Step 3: 选择图片
            const Text('持仓截图', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('上传该机构的持仓截图，AI 自动解析账户和持仓', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            if (isDesktopOrWeb) ...[
              _buildDesktopImagePicker(),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: ocrState.isProcessing ? null : () => _pickImageMobile(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('拍照'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: ocrState.isProcessing ? null : _pickMultiImageMobile,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('选择多张'),
                    ),
                  ),
                ],
              ),
            ],

            // 图片预览
            if (_selectedImages.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(_selectedImages[i], height: 100, width: 80, fit: BoxFit.cover),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('已选 ${_selectedImages.length} 张图片', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
            ],

            const SizedBox(height: 16),

            // 处理状态
            if (ocrState.isProcessing) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        _totalImages > 1
                            ? 'AI 正在分析第 $_processedCount/$_totalImages 张截图...'
                            : 'AI 正在分析截图...',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      Text('AI 正在分析截图...', style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ],

            if (ocrState.errorMessage != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(ocrState.errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
                  ],
                ),
              ),
            ],

            // 识别结果
            if (ocrState.results.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('识别结果', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('共 ${ocrState.results.length} 条', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 4),
              const Text('点击可编辑，左滑可删除', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
              const SizedBox(height: 12),
              ...List.generate(ocrState.results.length, (index) {
                final r = ocrState.results[index];
                final typeLabel = _assetTypeLabel(r.assetType);
                return Dismissible(
                  key: ValueKey('${r.code}_$index'),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => ref.read(ocrResultProvider.notifier).removeResult(index),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: AppColors.error,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => _editResult(index, r),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            // 类型标签
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(typeLabel, style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                            ),
                            if (r.needsCurrencyConversion) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(r.currency, style: TextStyle(fontSize: 10, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
                              ),
                            ],
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${r.code != "unknown" ? "${r.code} · " : ""}数量:${r.quantity} · 现价:${r.currentPrice}',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${ExchangeRateService.currencySymbols[r.currency] ?? "¥"}${r.marketValue.toStringAsFixed(0)}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                ),
                                const Icon(Icons.edit, size: 14, color: AppColors.textHint),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _confirmImport,
                  icon: const Icon(Icons.check),
                  label: Text('确认导入 ${ocrState.results.length} 条资产'),
                ),
              ),
            ],

            if (!ocrState.isProcessing && ocrState.results.isEmpty && ocrState.errorMessage == null && _selectedImages.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.auto_awesome, size: 48, color: AppColors.textHint),
                      SizedBox(height: 12),
                      Text('选择机构后上传持仓截图', style: TextStyle(color: AppColors.textHint)),
                      SizedBox(height: 4),
                      Text('AI 自动解析账户和持仓数据', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
                    ],
                  ),
                ),
              ),

            // 手动录入入口
            const SizedBox(height: 20),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  if (widget.accountId.isNotEmpty) {
                    context.push('/holding-form?accountId=${widget.accountId}');
                  } else {
                    context.push('/account-form${_selectedMemberId != null ? '?memberId=$_selectedMemberId' : ''}');
                  }
                },
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('手动录入'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _isDesktop {
    return const [TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux]
        .contains(Theme.of(context).platform);
  }

  Widget _buildDesktopImagePicker() {
    return InkWell(
      onTap: ref.read(ocrResultProvider).isProcessing ? null : _pickImageDesktop,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 2),
          borderRadius: BorderRadius.circular(12),
          color: AppColors.primary.withValues(alpha: 0.03),
        ),
        child: Column(
          children: [
            Icon(Icons.upload_file, size: 40, color: AppColors.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 8),
            const Text('点击选择持仓截图（可多选）', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('支持同时选择多张截图，自动合并去重', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImageDesktop() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    final imageList = result.files
        .where((f) => f.bytes != null)
        .map((f) => f.bytes!)
        .toList();
    if (imageList.isEmpty) return;
    setState(() => _selectedImages = imageList);
    _processMultiImages(imageList);
  }

  Future<void> _pickImageMobile(ImageSource source) async {
    final image = await _picker.pickImage(source: source, imageQuality: 90);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    setState(() => _selectedImages = [bytes]);
    _processMultiImages([bytes]);
  }

  Future<void> _pickMultiImageMobile() async {
    final images = await _picker.pickMultiImage(imageQuality: 90);
    if (images.isEmpty) return;
    final imageList = <Uint8List>[];
    for (final img in images) {
      imageList.add(await img.readAsBytes());
    }
    setState(() => _selectedImages = imageList);
    _processMultiImages(imageList);
  }

  /// 处理多张图片：逐张识别、合并去重
  Future<void> _processMultiImages(List<Uint8List> images) async {
    ref.read(ocrResultProvider.notifier).setProcessing();
    setState(() { _processedCount = 0; _totalImages = images.length; });

    final allHoldings = <ParsedHolding>[];
    final institution = _selectedInstitution.isNotEmpty ? _selectedInstitution : '未知机构';

    try {
      for (int i = 0; i < images.length; i++) {
        setState(() => _processedCount = i + 1);
        try {
          final text = await OcrService.recognizeFromBytes(images[i], institution: institution);
          final holdings = OcrParser.parseHoldingText(text);
          allHoldings.addAll(holdings);
        } catch (e) {
          debugPrint('图片 ${i + 1} 识别失败: $e');
        }
      }

      // 去重：按 code+name 合并，保留最新的（后出现的覆盖前面的）
      final deduped = <String, ParsedHolding>{};
      for (final h in allHoldings) {
        final key = h.code != 'unknown' && h.code.isNotEmpty ? h.code : h.name;
        deduped[key] = h;
      }

      final results = deduped.values.toList();

      if (results.isEmpty) {
        ref.read(ocrResultProvider.notifier).setError(
          '未能从 ${images.length} 张截图中识别出持仓数据\n\n'
          '请确保截图包含持仓信息。',
        );
      } else {
        ref.read(ocrResultProvider.notifier).setResults(results);
      }
    } on OcrException catch (e) {
      ref.read(ocrResultProvider.notifier).setError(
        '${e.message}\n\n建议：\n• 确保截图清晰、完整\n• 如持续失败，可尝试裁剪只保留持仓数据区域',
      );
    } catch (e) {
      ref.read(ocrResultProvider.notifier).setError('处理失败: $e');
    }
  }

  Future<void> _confirmImport() async {
    var results = ref.read(ocrResultProvider).results.toList();
    if (results.isEmpty) return;

    // 检查是否有需要汇率转换的持仓
    final foreignCurrencies = results
        .where((r) => r.needsCurrencyConversion)
        .map((r) => r.currency)
        .toSet();

    if (foreignCurrencies.isNotEmpty && mounted) {
      final rates = await ExchangeRateService.getRates(foreignCurrencies);
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('汇率转换确认'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('以下持仓将按实时汇率转换为人民币：', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 12),
                ...rates.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text(e.key, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.orange.shade700)),
                      ),
                      const SizedBox(width: 8),
                      Text('1 ${ExchangeRateService.currencyNames[e.key] ?? e.key} = ¥${e.value.toStringAsFixed(4)}', style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                )),
                const Divider(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView(
                    shrinkWrap: true,
                    children: results.where((r) => r.needsCurrencyConversion).map((r) {
                      final rate = rates[r.currency] ?? 1.0;
                      final symbol = ExchangeRateService.currencySymbols[r.currency] ?? '';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(
                              '现价: $symbol${r.currentPrice.toStringAsFixed(2)} → ¥${(r.currentPrice * rate).toStringAsFixed(2)}  '
                              '市值: $symbol${r.marketValue.toStringAsFixed(0)} → ¥${(r.marketValue * rate).toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('保留原币')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('转换为人民币')),
          ],
        ),
      );

      if (confirmed == true) {
        results = results.map((r) {
          if (!r.needsCurrencyConversion) return r;
          final rate = rates[r.currency] ?? 1.0;
          return r.copyWith(
            costPrice: r.costPrice * rate,
            currentPrice: r.currentPrice * rate,
            marketValue: r.marketValue * rate,
            currency: 'CNY',
          );
        }).toList();
        ref.read(ocrResultProvider.notifier).setResults(results);
      }
      if (!mounted) return;
    }

    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final uuid = const Uuid();
    final institution = _selectedInstitution.isNotEmpty ? _selectedInstitution : '未知机构';

    // 确定目标 accountId
    String targetAccountId = widget.accountId;

    if (targetAccountId.isEmpty) {
      final memberId = _selectedMemberId;
      if (memberId == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择所属成员')));
        return;
      }
      targetAccountId = uuid.v4();
      await db.insertAccount(AccountsCompanion(
        id: Value(targetAccountId),
        memberId: Value(memberId),
        name: Value('$institution 账户'),
        type: Value('securities'),
        institution: Value(institution),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
    }

    // 获取该账户下的已有持仓
    final existingHoldings = await db.getHoldingsByAccount(targetAccountId);

    int updatedCount = 0;
    int addedCount = 0;
    final matchedExistingIds = <String>{};

    for (final r in results) {
      final aiType = AssetType.values.where((e) => e.name == r.assetType).firstOrNull;
      final type = aiType ?? AssetClassifier.classify(r.code, r.name);

      // 尝试匹配已有持仓：优先按代码匹配，其次按名称匹配
      final existing = existingHoldings.where((h) {
        if (r.code != 'unknown' && r.code.isNotEmpty && h.assetCode == r.code) return true;
        if (h.assetName == r.name) return true;
        return false;
      }).firstOrNull;

      if (existing != null) {
        // 更新已有持仓
        matchedExistingIds.add(existing.id);
        await db.updateHolding(HoldingsCompanion(
          id: Value(existing.id),
          accountId: Value(targetAccountId),
          assetCode: Value(r.code != 'unknown' ? r.code : existing.assetCode),
          assetName: Value(r.name),
          assetType: Value(type.name),
          quantity: Value(r.quantity),
          costPrice: Value(r.costPrice > 0 ? r.costPrice : existing.costPrice),
          currentPrice: Value(r.currentPrice),
          tags: Value(existing.tags),
          notes: Value(existing.notes),
          createdAt: Value(existing.createdAt),
          updatedAt: Value(now),
        ));
        updatedCount++;
      } else {
        // 新增持仓
        await db.insertHolding(HoldingsCompanion(
          id: Value(uuid.v4()),
          accountId: Value(targetAccountId),
          assetCode: Value(r.code),
          assetName: Value(r.name),
          assetType: Value(type.name),
          quantity: Value(r.quantity),
          costPrice: Value(r.costPrice),
          currentPrice: Value(r.currentPrice),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
        addedCount++;
      }
    }

    // 检查不在新截图中的旧持仓，提示用户是否删除
    final unmatchedHoldings = existingHoldings.where((h) => !matchedExistingIds.contains(h.id)).toList();
    int deletedCount = 0;

    if (unmatchedHoldings.isNotEmpty && mounted) {
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('发现未匹配的旧持仓'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '以下 ${unmatchedHoldings.length} 条持仓在新截图中未出现，是否删除？',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: unmatchedHoldings.length,
                    itemBuilder: (_, i) {
                      final h = unmatchedHoldings[i];
                      final mv = h.quantity * h.currentPrice;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(h.assetName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  Text(h.assetCode, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                                ],
                              ),
                            ),
                            Text('¥${mv.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('保留'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      );

      if (shouldDelete == true) {
        for (final h in unmatchedHoldings) {
          await db.deleteHolding(h.id);
          deletedCount++;
        }
      }
    }

    ref.read(autoSyncProvider).triggerAutoSync();
    ref.invalidate(allHoldingsProvider);
    ref.invalidate(allAccountsProvider);
    ref.read(ocrResultProvider.notifier).clear();

    if (mounted) {
      final parts = <String>[];
      if (addedCount > 0) parts.add('新增$addedCount条');
      if (updatedCount > 0) parts.add('更新$updatedCount条');
      if (deletedCount > 0) parts.add('删除$deletedCount条');
      final msg = parts.isEmpty ? '无变化' : parts.join('，');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「$institution」$msg')));
      context.pop();
    }
  }

  String _assetTypeLabel(String type) {
    const labels = {
      'aStock': 'A股', 'hkStock': '港股', 'usStock': '美股',
      'indexETF': 'ETF', 'qdii': 'QDII', 'dividendFund': '红利',
      'nasdaqETF': '纳指', 'bondFund': '债基', 'moneyFund': '货基',
      'mixedFund': '基金', 'wealth': '理财', 'deposit': '存款', 'other': '其他',
    };
    return labels[type] ?? '资产';
  }

  Future<void> _editResult(int index, ParsedHolding r) async {
    final nameC = TextEditingController(text: r.name);
    final codeC = TextEditingController(text: r.code == 'unknown' ? '' : r.code);
    final qtyC = TextEditingController(text: r.quantity.toString());
    final costC = TextEditingController(text: r.costPrice.toString());
    final priceC = TextEditingController(text: r.currentPrice.toString());
    final mvC = TextEditingController(text: r.marketValue.toString());
    String selectedType = r.assetType.isNotEmpty ? r.assetType : 'other';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('编辑资产'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameC, decoration: const InputDecoration(labelText: '名称', isDense: true)),
                const SizedBox(height: 10),
                TextField(controller: codeC, decoration: const InputDecoration(labelText: '代码', isDense: true, hintText: '如 600519、AAPL')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: '资产类型', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'aStock', child: Text('A股')),
                    DropdownMenuItem(value: 'hkStock', child: Text('港股')),
                    DropdownMenuItem(value: 'usStock', child: Text('美股')),
                    DropdownMenuItem(value: 'indexETF', child: Text('指数ETF')),
                    DropdownMenuItem(value: 'nasdaqETF', child: Text('纳指ETF')),
                    DropdownMenuItem(value: 'qdii', child: Text('QDII')),
                    DropdownMenuItem(value: 'dividendFund', child: Text('红利基金')),
                    DropdownMenuItem(value: 'bondFund', child: Text('债券基金')),
                    DropdownMenuItem(value: 'moneyFund', child: Text('货币基金')),
                    DropdownMenuItem(value: 'mixedFund', child: Text('混合基金')),
                    DropdownMenuItem(value: 'wealth', child: Text('银行理财')),
                    DropdownMenuItem(value: 'deposit', child: Text('存款')),
                    DropdownMenuItem(value: 'other', child: Text('其他')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedType = v ?? 'other'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: TextField(controller: qtyC, decoration: const InputDecoration(labelText: '数量', isDense: true), keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: costC, decoration: const InputDecoration(labelText: '成本价', isDense: true), keyboardType: TextInputType.number)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: TextField(controller: priceC, decoration: const InputDecoration(labelText: '现价', isDense: true), keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: mvC, decoration: const InputDecoration(labelText: '市值', isDense: true), keyboardType: TextInputType.number)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );

    if (saved == true) {
      final updated = r.copyWith(
        name: nameC.text.trim().isNotEmpty ? nameC.text.trim() : r.name,
        code: codeC.text.trim().isNotEmpty ? codeC.text.trim() : 'unknown',
        quantity: double.tryParse(qtyC.text) ?? r.quantity,
        costPrice: double.tryParse(costC.text) ?? r.costPrice,
        currentPrice: double.tryParse(priceC.text) ?? r.currentPrice,
        marketValue: double.tryParse(mvC.text) ?? r.marketValue,
        assetType: selectedType,
      );
      ref.read(ocrResultProvider.notifier).updateResult(index, updated);
    }

    nameC.dispose(); codeC.dispose(); qtyC.dispose();
    costC.dispose(); priceC.dispose(); mvC.dispose();
  }
}
