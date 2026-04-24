import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import '../../data/models/asset_summary_model.dart';

/// Dashboard 展示大分类 — 按投资行业惯例分组
enum CategoryGroup {
  aStock('A股', Icons.candlestick_chart, Color(0xFFE53935)),
  hkStock('港股', Icons.show_chart, Color(0xFFFF7043)),
  usStock('美股', Icons.stacked_line_chart, Color(0xFF5C6BC0)),
  indexFund('指数基金', Icons.trending_up, AppColors.info),        // 被动指数：ETF/LOF/指数增强
  activeFund('主动基金', Icons.auto_awesome, Color(0xFF7E57C2)),   // 主动管理：混合/QDII权益
  fixedIncome('固收基金', Icons.shield, Color(0xFF26A69A)),         // 债券基金/货币基金
  wealth('银行理财', Icons.account_balance, AppColors.warning),     // 银行理财产品
  deposit('现金存款', Icons.savings, AppColors.success),            // 活期/定期存款
  otherAssets('其他资产', Icons.category, Color(0xFF78909C));       // 房产/车辆/其他

  const CategoryGroup(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

/// AssetType → CategoryGroup 映射
const _groupMapping = <AssetType, CategoryGroup>{
  // 股票
  AssetType.aStock: CategoryGroup.aStock,
  AssetType.hkStock: CategoryGroup.hkStock,
  AssetType.usStock: CategoryGroup.usStock,
  // 基金
  AssetType.indexFund: CategoryGroup.indexFund,
  AssetType.activeFund: CategoryGroup.activeFund,
  // 固收型基金
  AssetType.bondFund: CategoryGroup.fixedIncome,
  AssetType.moneyFund: CategoryGroup.fixedIncome,
  // 理财
  AssetType.wealth: CategoryGroup.wealth,
  AssetType.structuredDeposit: CategoryGroup.wealth,
  AssetType.treasuryRepo: CategoryGroup.wealth,
  AssetType.insurance: CategoryGroup.wealth,
  // 存款（活期/定期/大额存单/通知存款）
  AssetType.deposit: CategoryGroup.deposit,
  AssetType.fixedDeposit: CategoryGroup.deposit,
  AssetType.largeDeposit: CategoryGroup.deposit,
  AssetType.noticeDeposit: CategoryGroup.deposit,
  // 其他资产（房产、车辆、黄金等）
  AssetType.realEstate: CategoryGroup.otherAssets,
  AssetType.vehicle: CategoryGroup.otherAssets,
  AssetType.gold: CategoryGroup.otherAssets,
  AssetType.other: CategoryGroup.otherAssets,
};

/// 每个分类组应展示的字段模式
enum HoldingDisplayMode {
  /// 股票/权益基金：代码、数量、成本价、现价、盈亏%
  tradable,
  /// 固收基金：名称、份额、净值、总市值、收益额
  fixedIncome,
  /// 银行理财：名称、总市值、总成本、收益额
  wealth,
  /// 存款：名称、金额
  deposit,
}

/// 根据 CategoryGroup 获取展示模式
HoldingDisplayMode getDisplayMode(CategoryGroup group) {
  switch (group) {
    case CategoryGroup.aStock:
    case CategoryGroup.hkStock:
    case CategoryGroup.usStock:
    case CategoryGroup.indexFund:
    case CategoryGroup.activeFund:
      return HoldingDisplayMode.tradable;
    case CategoryGroup.fixedIncome:
      return HoldingDisplayMode.fixedIncome;
    case CategoryGroup.wealth:
      return HoldingDisplayMode.wealth;
    case CategoryGroup.deposit:
      return HoldingDisplayMode.deposit;
    case CategoryGroup.otherAssets:
      return HoldingDisplayMode.wealth; // 其他资产按市值展示
  }
}

/// 根据 AssetType 获取展示模式
HoldingDisplayMode getDisplayModeForAssetType(AssetType type) {
  final group = _groupMapping[type];
  if (group == null) return HoldingDisplayMode.tradable;
  return getDisplayMode(group);
}

class GroupedCategoryData {
  final CategoryGroup group;
  final double totalMarketValue;
  final double profitLoss;
  final double proportion;
  final int holdingCount;

  const GroupedCategoryData({
    required this.group,
    required this.totalMarketValue,
    required this.profitLoss,
    required this.proportion,
    required this.holdingCount,
  });
}

/// 将细分 AssetSummaryModel 合并为大类
List<GroupedCategoryData> groupCategories(List<AssetSummaryModel> categories) {
  final map = <CategoryGroup, _Acc>{};

  double grandTotal = 0;
  for (final c in categories) {
    final group = _groupMapping[c.assetType];
    if (group == null) continue;
    map.putIfAbsent(group, () => _Acc());
    map[group]!.mv += c.totalMarketValue;
    map[group]!.pnl += c.profitLoss;
    map[group]!.count += c.holdingCount;
    grandTotal += c.totalMarketValue;
  }

  final result = <GroupedCategoryData>[];
  for (final g in CategoryGroup.values) {
    final acc = map[g];
    if (acc == null) continue;
    result.add(GroupedCategoryData(
      group: g,
      totalMarketValue: acc.mv,
      profitLoss: acc.pnl,
      proportion: grandTotal > 0 ? acc.mv / grandTotal * 100 : 0,
      holdingCount: acc.count,
    ));
  }
  result.sort((a, b) => b.totalMarketValue.compareTo(a.totalMarketValue));
  return result;
}

/// 根据分组名反查对应的 AssetType 列表
List<AssetType> getAssetTypesForGroup(CategoryGroup group) {
  return _groupMapping.entries
      .where((e) => e.value == group)
      .map((e) => e.key)
      .toList();
}

/// 根据 AssetType 查找所属分组
CategoryGroup? getGroupForAssetType(AssetType type) {
  return _groupMapping[type];
}

/// 根据 AssetType name 字符串查找所属分组
CategoryGroup? getGroupForAssetTypeName(String assetTypeName) {
  final type = AssetType.values.where((e) => e.name == assetTypeName).firstOrNull;
  if (type == null) return null;
  return _groupMapping[type];
}

class _Acc {
  double mv = 0, pnl = 0;
  int count = 0;
}
