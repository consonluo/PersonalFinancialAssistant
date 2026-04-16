import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/asset_classifier.dart';
import '../../providers/database_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/holding_provider.dart';
import '../../data/database/app_database.dart';

class HoldingFormPage extends ConsumerStatefulWidget {
  final String? holdingId;
  final String? accountId;
  const HoldingFormPage({super.key, this.holdingId, this.accountId});

  @override
  ConsumerState<HoldingFormPage> createState() => _HoldingFormPageState();
}

class _HoldingFormPageState extends ConsumerState<HoldingFormPage> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _qtyController = TextEditingController();
  final _costController = TextEditingController();
  final _priceController = TextEditingController();
  AssetType _assetType = AssetType.aStock;
  bool _isEdit = false;
  String? _existingAccountId;

  @override
  void initState() {
    super.initState();
    if (widget.holdingId != null) {
      _isEdit = true;
      _loadHolding();
    }
  }

  Future<void> _loadHolding() async {
    final db = ref.read(databaseProvider);
    final h = await db.getHoldingById(widget.holdingId!);
    if (h != null && mounted) {
      _codeController.text = h.assetCode;
      _nameController.text = h.assetName;
      _qtyController.text = h.quantity.toString();
      _costController.text = h.costPrice.toString();
      _priceController.text = h.currentPrice.toString();
      _existingAccountId = h.accountId;
      _assetType = AssetType.values.firstWhere((e) => e.name == h.assetType, orElse: () => AssetType.other);
      setState(() {});
    }
  }

  void _autoClassify() {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    if (code.isNotEmpty || name.isNotEmpty) {
      setState(() => _assetType = AssetClassifier.classify(code, name));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑持仓' : '添加持仓'),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              onPressed: _deleteHolding,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(controller: _codeController, decoration: const InputDecoration(labelText: '证券代码', hintText: '如 600519'), onChanged: (_) => _autoClassify()),
            const SizedBox(height: 16),
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: '名称', hintText: '如 贵州茅台'), onChanged: (_) => _autoClassify()),
            const SizedBox(height: 16),
            DropdownButtonFormField<AssetType>(
              value: _assetType,
              decoration: const InputDecoration(labelText: '资产类型'),
              items: AssetType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(),
              onChanged: (v) => setState(() => _assetType = v ?? AssetType.other),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _qtyController,
              decoration: const InputDecoration(
                labelText: '持仓数量/份额 *',
                hintText: '如 1000',
                helperText: '股票填股数，基金填份额',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _costController,
              decoration: const InputDecoration(
                labelText: '成本价 *',
                hintText: '如 15.50',
                helperText: '买入均价，用于计算盈亏',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _priceController,
              decoration: InputDecoration(
                labelText: '现价',
                hintText: '留空则取成本价',
                helperText: _canAutoUpdate(_assetType)
                    ? '股票/基金会自动更新行情价格'
                    : '理财/存款等需手动维护现价',
                suffixIcon: _isEdit && _canAutoUpdate(_assetType)
                    ? Tooltip(
                        message: '自动行情更新中',
                        child: Icon(Icons.sync, size: 18, color: Colors.green.shade400),
                      )
                    : null,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 32),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _save, child: const Text('保存'))),
          ],
        ),
      ),
    );
  }

  /// 是否支持自动更新行情（股票和基金类）
  static bool _canAutoUpdate(AssetType type) {
    return const {
      AssetType.aStock, AssetType.hkStock, AssetType.usStock,
      AssetType.indexETF, AssetType.qdii, AssetType.dividendFund,
      AssetType.nasdaqETF, AssetType.bondFund, AssetType.moneyFund,
      AssetType.mixedFund,
    }.contains(type);
  }

  Future<void> _save() async {
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final accountId = widget.accountId ?? _existingAccountId ?? '';
    final costPrice = double.tryParse(_costController.text) ?? 0;
    final currentPrice = double.tryParse(_priceController.text) ?? costPrice;

    if (_isEdit) {
      await db.updateHolding(HoldingsCompanion(
        id: Value(widget.holdingId!),
        accountId: Value(accountId),
        assetCode: Value(_codeController.text.trim()),
        assetName: Value(_nameController.text.trim()),
        assetType: Value(_assetType.name),
        quantity: Value(double.tryParse(_qtyController.text) ?? 0),
        costPrice: Value(costPrice),
        currentPrice: Value(currentPrice),
        updatedAt: Value(now),
      ));
    } else {
      await db.insertHolding(HoldingsCompanion(
        id: Value(const Uuid().v4()),
        accountId: Value(accountId),
        assetCode: Value(_codeController.text.trim()),
        assetName: Value(_nameController.text.trim()),
        assetType: Value(_assetType.name),
        quantity: Value(double.tryParse(_qtyController.text) ?? 0),
        costPrice: Value(costPrice),
        currentPrice: Value(currentPrice),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
    }
    ref.read(autoSyncProvider).triggerAutoSync();
    ref.invalidate(allHoldingsProvider);
    if (mounted) {
      if (Navigator.of(context).canPop()) {
        context.pop();
      } else {
        context.go('/accounts');
      }
    }
  }

  Future<void> _deleteHolding() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除持仓'),
        content: Text('确定删除「${_nameController.text}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm == true && widget.holdingId != null) {
      final db = ref.read(databaseProvider);
      await db.deleteHolding(widget.holdingId!);
      ref.read(autoSyncProvider).triggerAutoSync();
      ref.invalidate(allHoldingsProvider);
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          context.pop();
        } else {
          context.go('/accounts');
        }
      }
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _qtyController.dispose();
    _costController.dispose();
    _priceController.dispose();
    super.dispose();
  }
}
