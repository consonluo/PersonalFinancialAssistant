import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/asset_classifier.dart';
import '../../core/utils/category_group.dart';
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
  // 理财/存款用的总额输入
  final _totalAmountController = TextEditingController();
  final _totalCostController = TextEditingController();
  AssetType _assetType = AssetType.aStock;
  bool _isEdit = false;
  String? _existingAccountId;

  /// 当前类型的输入模式
  _InputMode get _inputMode {
    final dm = getDisplayModeForAssetType(_assetType);
    switch (dm) {
      case HoldingDisplayMode.deposit:
        return _InputMode.deposit;
      case HoldingDisplayMode.wealth:
      case HoldingDisplayMode.fixedIncome:
        return _InputMode.wealth;
      case HoldingDisplayMode.tradable:
        return _InputMode.stock;
    }
  }

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
      // 理财/存款模式下，填充总额字段
      if (_inputMode == _InputMode.deposit) {
        _totalAmountController.text = (h.quantity * h.currentPrice).toString();
      } else if (_inputMode == _InputMode.wealth) {
        _totalAmountController.text = (h.quantity * h.currentPrice).toString();
        _totalCostController.text = (h.quantity * h.costPrice).toString();
      }
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
    final mode = _inputMode;
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 资产类型选择（放在最前面）
                DropdownButtonFormField<AssetType>(
                  value: _assetType,
                  decoration: const InputDecoration(labelText: '资产类型'),
                  items: AssetType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(),
                  onChanged: (v) => setState(() => _assetType = v ?? AssetType.other),
                ),
                const SizedBox(height: 8),
                // 输入模式提示
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    mode == _InputMode.deposit
                        ? '存款：只需填写名称和金额'
                        : mode == _InputMode.wealth
                            ? '理财/固收基金：填写名称、总市值和总成本，份额净值选填'
                            : '股票/权益基金：填写代码、名称、数量、成本价',
                    style: const TextStyle(fontSize: 12, color: AppColors.info),
                  ),
                ),
                const SizedBox(height: 16),
                // 名称（所有类型都需要）
                TextField(controller: _nameController, decoration: InputDecoration(
                  labelText: '名称 *',
                  hintText: mode == _InputMode.deposit ? '如 XX银行定期' : mode == _InputMode.wealth ? '如 XX理财产品' : '如 贵州茅台',
                ), onChanged: (_) => _autoClassify()),
                const SizedBox(height: 16),
                // 代码（存款不需要，理财选填）
                if (mode != _InputMode.deposit) ...[
                  TextField(controller: _codeController, decoration: InputDecoration(
                    labelText: mode == _InputMode.wealth ? '产品代码（选填）' : '证券代码 *',
                    hintText: mode == _InputMode.wealth ? '理财产品编号，没有可不填' : '如 600519',
                  ), onChanged: (_) => _autoClassify()),
                  const SizedBox(height: 16),
                ],

                if (mode == _InputMode.deposit) ...[
                  // 存款：只需要金额
                  TextField(
                    controller: _totalAmountController,
                    decoration: const InputDecoration(labelText: '存款金额 *', hintText: '如 100000'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ] else if (mode == _InputMode.wealth) ...[
                  // 理财：总市值 + 总成本（必填），份额/单价选填
                  TextField(
                    controller: _totalAmountController,
                    decoration: const InputDecoration(labelText: '当前总市值 *', hintText: '如 105000', helperText: '截图或APP上显示的当前总金额'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _totalCostController,
                    decoration: const InputDecoration(labelText: '投入总成本 *', hintText: '如 100000', helperText: '实际投入的本金总额'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  // 可选的详细字段
                  ExpansionTile(
                    title: const Text('详细信息（选填）', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    children: [
                      TextField(
                        controller: _qtyController,
                        decoration: const InputDecoration(labelText: '持有份额', hintText: '如有份额信息可填'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _costController,
                        decoration: const InputDecoration(labelText: '成本净值', hintText: '如有每份净值可填'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _priceController,
                        decoration: const InputDecoration(labelText: '当前净值', hintText: '如有最新净值可填'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ],
                  ),
                ] else ...[
                  // 股票/基金：完整字段
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
                          : '需手动维护现价',
                      suffixIcon: _isEdit && _canAutoUpdate(_assetType)
                          ? Tooltip(
                              message: '自动行情更新中',
                              child: Icon(Icons.sync, size: 18, color: Colors.green.shade400),
                            )
                          : null,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _save, child: const Text('保存'))),
              ],
            ),
          ),
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
    final mode = _inputMode;

    // ---- 必填项校验 ----
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('请输入名称');
      return;
    }
    if (accountId.isEmpty) {
      _showError('无法保存：未关联到任何账户，请从账户页面进入添加');
      return;
    }

    double quantity;
    double costPrice;
    double currentPrice;
    String assetCode = _codeController.text.trim();

    if (mode == _InputMode.deposit) {
      final amount = double.tryParse(_totalAmountController.text) ?? 0;
      if (amount <= 0) { _showError('请输入存款金额'); return; }
      quantity = 1;
      costPrice = amount;
      currentPrice = amount;
      if (assetCode.isEmpty) assetCode = 'DEPOSIT';
    } else if (mode == _InputMode.wealth) {
      final totalMv = double.tryParse(_totalAmountController.text) ?? 0;
      final totalCost = double.tryParse(_totalCostController.text) ?? totalMv;
      if (totalMv <= 0) { _showError('请输入当前总市值'); return; }
      final qtyInput = double.tryParse(_qtyController.text);
      if (qtyInput != null && qtyInput > 0) {
        quantity = qtyInput;
        costPrice = double.tryParse(_costController.text) ?? (totalCost / quantity);
        currentPrice = double.tryParse(_priceController.text) ?? (totalMv / quantity);
      } else {
        quantity = 1;
        costPrice = totalCost;
        currentPrice = totalMv;
      }
      if (assetCode.isEmpty) assetCode = 'WEALTH';
    } else {
      quantity = double.tryParse(_qtyController.text) ?? 0;
      costPrice = double.tryParse(_costController.text) ?? 0;
      currentPrice = double.tryParse(_priceController.text) ?? costPrice;
      if (quantity <= 0) { _showError('请输入持仓数量'); return; }
      if (costPrice <= 0) { _showError('请输入成本价'); return; }
    }

    try {
      if (_isEdit) {
        final existing = await db.getHoldingById(widget.holdingId!);
        await db.updateHolding(HoldingsCompanion(
          id: Value(widget.holdingId!),
          accountId: Value(accountId),
          assetCode: Value(assetCode),
          assetName: Value(name),
          assetType: Value(_assetType.name),
          quantity: Value(quantity),
          costPrice: Value(costPrice),
          currentPrice: Value(currentPrice),
          tags: Value(existing?.tags ?? ''),
          notes: Value(existing?.notes ?? ''),
          createdAt: Value(existing?.createdAt ?? now),
          updatedAt: Value(now),
        ));
      } else {
        await db.insertHolding(HoldingsCompanion(
          id: Value(const Uuid().v4()),
          accountId: Value(accountId),
          assetCode: Value(assetCode),
          assetName: Value(name),
          assetType: Value(_assetType.name),
          quantity: Value(quantity),
          costPrice: Value(costPrice),
          currentPrice: Value(currentPrice),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
      }
      ref.read(autoSyncProvider).triggerAutoSync();
      ref.invalidate(allHoldingsProvider);
      if (accountId.isNotEmpty) {
        ref.invalidate(holdingsByAccountProvider(accountId));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_isEdit ? "更新" : "添加"}成功：$name')),
        );
        if (Navigator.of(context).canPop()) {
          context.pop();
        } else {
          context.go('/accounts');
        }
      }
    } catch (e) {
      _showError('保存失败: $e');
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error),
      );
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
      final accountId = widget.accountId ?? _existingAccountId ?? '';
      await db.deleteHolding(widget.holdingId!);
      ref.read(autoSyncProvider).triggerAutoSync();
      ref.invalidate(allHoldingsProvider);
      if (accountId.isNotEmpty) {
        ref.invalidate(holdingsByAccountProvider(accountId));
      }
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
    _totalAmountController.dispose();
    _totalCostController.dispose();
    super.dispose();
  }
}

/// 输入模式
enum _InputMode { stock, wealth, deposit }
