import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import '../data/models/asset_summary_model.dart';
import '../core/constants/app_constants.dart';
import 'database_provider.dart';
import 'holding_provider.dart';
import 'market_provider.dart';

/// 资产汇总 Provider
final assetSummaryProvider = Provider<FamilyAssetOverview>((ref) {
  final holdingsAsync = ref.watch(allHoldingsProvider);
  final marketData = ref.watch(marketDataProvider);

  final holdings = holdingsAsync.valueOrNull ?? [];
  if (holdings.isEmpty) return const FamilyAssetOverview();

  // 按分类聚合
  final categoryMap = <AssetType, _CategoryAcc>{};
  double totalInvestment = 0;
  double totalTodayChange = 0;

  for (final h in holdings) {
    final type = AssetType.values.firstWhere(
      (e) => e.name == h.assetType,
      orElse: () => AssetType.other,
    );

    final market = marketData[h.assetCode];
    final currentPrice = market?.price ?? h.currentPrice;
    final mv = h.quantity * currentPrice;
    final cost = h.quantity * h.costPrice;
    final todayChg = market != null ? mv * market.changePercent / 100 : 0.0;

    categoryMap.putIfAbsent(type, () => _CategoryAcc());
    categoryMap[type]!.totalMV += mv;
    categoryMap[type]!.totalCost += cost;
    categoryMap[type]!.todayChange += todayChg;
    categoryMap[type]!.count++;

    totalInvestment += mv;
    totalTodayChange += todayChg;
  }

  final categories = categoryMap.entries.map((e) {
    final acc = e.value;
    return AssetSummaryModel(
      assetType: e.key,
      categoryName: e.key.label,
      totalMarketValue: acc.totalMV,
      totalCost: acc.totalCost,
      profitLoss: acc.totalMV - acc.totalCost,
      profitLossPercent:
          acc.totalCost != 0 ? (acc.totalMV - acc.totalCost) / acc.totalCost * 100 : 0,
      proportion: totalInvestment != 0 ? acc.totalMV / totalInvestment * 100 : 0,
      holdingCount: acc.count,
      todayChange: acc.todayChange,
    );
  }).toList()
    ..sort((a, b) => b.totalMarketValue.compareTo(a.totalMarketValue));

  return FamilyAssetOverview(
    totalAssets: totalInvestment,
    totalInvestment: totalInvestment,
    todayChange: totalTodayChange,
    todayChangePercent:
        totalInvestment != 0 ? totalTodayChange / totalInvestment * 100 : 0,
    categories: categories,
  );
});

/// 按成员的资产汇总
final memberAssetProvider =
    FutureProvider.family<double, String>((ref, memberId) async {
  final db = ref.watch(databaseProvider);
  final accounts = await db.getAccountsByMember(memberId);
  double total = 0;
  for (final acc in accounts) {
    final holdings = await db.getHoldingsByAccount(acc.id);
    for (final h in holdings) {
      total += h.quantity * h.currentPrice;
    }
  }
  return total;
});

class _CategoryAcc {
  double totalMV = 0;
  double totalCost = 0;
  double todayChange = 0;
  int count = 0;
}
