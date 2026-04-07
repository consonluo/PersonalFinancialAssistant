import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import '../../data/models/asset_summary_model.dart';

/// Dashboard 首页的 6 大分类
enum CategoryGroup {
  aStock('A股', Icons.candlestick_chart, Color(0xFFE53935)),
  hkStock('港股', Icons.show_chart, Color(0xFFFF7043)),
  usStock('美股', Icons.ssid_chart, Color(0xFF5C6BC0)),
  fund('基金', Icons.pie_chart, AppColors.info),
  wealth('理财', Icons.account_balance, AppColors.warning),
  deposit('存款', Icons.savings, AppColors.success);

  const CategoryGroup(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

const _groupMapping = <AssetType, CategoryGroup>{
  AssetType.aStock: CategoryGroup.aStock,
  AssetType.hkStock: CategoryGroup.hkStock,
  AssetType.usStock: CategoryGroup.usStock,
  AssetType.indexETF: CategoryGroup.fund,
  AssetType.qdii: CategoryGroup.fund,
  AssetType.dividendFund: CategoryGroup.fund,
  AssetType.nasdaqETF: CategoryGroup.fund,
  AssetType.mixedFund: CategoryGroup.fund,
  // 固收 / 现金管理类归入理财
  AssetType.bondFund: CategoryGroup.wealth,
  AssetType.moneyFund: CategoryGroup.wealth,
  AssetType.wealth: CategoryGroup.wealth,
  AssetType.deposit: CategoryGroup.deposit,
};

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
