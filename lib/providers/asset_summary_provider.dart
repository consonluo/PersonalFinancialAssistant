import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/asset_summary_model.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/exchange_rate_service.dart';
import 'account_provider.dart';
import 'holding_provider.dart';
import 'market_provider.dart';

/// 汇率缓存 Provider
final exchangeRatesProvider = FutureProvider<Map<String, double>>((ref) async {
  // 获取所有持仓的币种
  final holdings = ref.watch(allHoldingsProvider).valueOrNull ?? [];
  final currencies = holdings.map((h) => h.currency).toSet();
  
  // 预热汇率缓存
  await ExchangeRateService.getRates(currencies);
  return {for (final c in currencies) c: await ExchangeRateService.getRate(c)};
});

/// 资产汇总 Provider
final assetSummaryProvider = Provider<FamilyAssetOverview>((ref) {
  final holdingsAsync = ref.watch(allHoldingsProvider);
  final marketData = ref.watch(marketDataProvider);
  final ratesAsync = ref.watch(exchangeRatesProvider);

  final holdings = holdingsAsync.valueOrNull ?? [];
  if (holdings.isEmpty) return const FamilyAssetOverview();

  // 获取汇率
  final rates = ratesAsync.valueOrNull ?? {};
  double getRate(String currency) {
    if (currency == 'CNY' || currency.isEmpty) return 1.0;
    return rates[currency] ?? ExchangeRateService.getFallbackRate(currency);
  }

  // 按分类聚合（所有金额转换为 CNY）
  final categoryMap = <AssetType, _CategoryAcc>{};
  double totalInvestment = 0;
  double totalTodayChange = 0;

  for (final h in holdings) {
    final type = AssetType.values.firstWhere(
      (e) => e.name == h.assetType,
      orElse: () => AssetType.other,
    );

    final currency = h.currency.isEmpty ? 'CNY' : h.currency;
    final rate = getRate(currency);

    final market = marketData[h.assetCode];
    final currentPrice = market?.price ?? h.currentPrice;
    final mvCny = h.quantity * currentPrice * rate;
    final costCny = h.quantity * h.costPrice * rate;
    final todayChg = market != null ? mvCny * market.changePercent / 100 : 0.0;

    categoryMap.putIfAbsent(type, () => _CategoryAcc());
    categoryMap[type]!.totalMV += mvCny;
    categoryMap[type]!.totalCost += costCny;
    categoryMap[type]!.todayChange += todayChg;
    categoryMap[type]!.count++;

    totalInvestment += mvCny;
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

/// 按成员的资产汇总 — 监听 allHoldingsProvider 确保持仓变化后自动更新
final memberAssetProvider =
    Provider.family<double, String>((ref, memberId) {
  final allHoldings = ref.watch(allHoldingsProvider).valueOrNull ?? [];
  final accounts = ref.watch(allAccountsProvider).valueOrNull ?? [];
  final marketData = ref.watch(marketDataProvider);
  final ratesAsync = ref.watch(exchangeRatesProvider);

  // 找出该成员的所有账户 ID
  final memberAccountIds = accounts
      .where((a) => a.memberId == memberId)
      .map((a) => a.id)
      .toSet();

  // 获取汇率
  final rates = ratesAsync.valueOrNull ?? {};
  double getRate(String currency) {
    if (currency == 'CNY' || currency.isEmpty) return 1.0;
    return rates[currency] ?? ExchangeRateService.getFallbackRate(currency);
  }

  double total = 0;
  for (final h in allHoldings) {
    if (!memberAccountIds.contains(h.accountId)) continue;
    final mkt = marketData[h.assetCode];
    final price = mkt?.price ?? h.currentPrice;
    final currency = h.currency.isEmpty ? 'CNY' : h.currency;
    final rate = getRate(currency);
    total += h.quantity * price * rate;
  }
  return total;
});

class _CategoryAcc {
  double totalMV = 0;
  double totalCost = 0;
  double todayChange = 0;
  int count = 0;
}
