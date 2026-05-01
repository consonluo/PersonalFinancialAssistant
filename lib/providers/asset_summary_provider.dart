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
  final accounts = ref.watch(allAccountsProvider).valueOrNull ?? [];
  final currencies = holdings.map((h) => h.currency).toSet();
  for (final account in accounts) {
    if (account.type == AccountType.securities.name &&
        account.financingAmount > 0) {
      currencies.add(account.financingCurrency);
    }
  }

  // 预热汇率缓存
  await ExchangeRateService.getRates(currencies);
  return {for (final c in currencies) c: await ExchangeRateService.getRate(c)};
});

/// 证券账户融资负债（折算 CNY）
final accountFinancingLiabilityProvider = Provider<double>((ref) {
  final accounts = ref.watch(allAccountsProvider).valueOrNull ?? [];
  final rates = ref.watch(exchangeRatesProvider).valueOrNull ?? {};
  double getRate(String currency) {
    if (currency == 'CNY' || currency.isEmpty) return 1.0;
    return rates[currency] ?? ExchangeRateService.getFallbackRate(currency);
  }

  double total = 0;
  for (final account in accounts) {
    if (account.type != AccountType.securities.name) continue;
    if (account.financingAmount <= 0) continue;
    final currency =
        account.financingCurrency.isEmpty ? 'CNY' : account.financingCurrency;
    total += account.financingAmount * getRate(currency);
  }
  return total;
});

/// 指定成员的证券账户融资负债（折算 CNY）
final memberAccountFinancingLiabilityProvider =
    Provider.family<double, String>((ref, memberId) {
  final accounts = ref.watch(allAccountsProvider).valueOrNull ?? [];
  final rates = ref.watch(exchangeRatesProvider).valueOrNull ?? {};
  double getRate(String currency) {
    if (currency == 'CNY' || currency.isEmpty) return 1.0;
    return rates[currency] ?? ExchangeRateService.getFallbackRate(currency);
  }

  double total = 0;
  for (final account in accounts) {
    if (account.memberId != memberId) continue;
    if (account.type != AccountType.securities.name) continue;
    if (account.financingAmount <= 0) continue;
    final currency =
        account.financingCurrency.isEmpty ? 'CNY' : account.financingCurrency;
    total += account.financingAmount * getRate(currency);
  }
  return total;
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
  // holdingCount 按 (assetType, assetCode) 去重，避免多账户同代码重复计数
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

    final acc = categoryMap.putIfAbsent(type, () => _CategoryAcc());
    acc.totalMV += mvCny;
    acc.totalCost += costCny;
    acc.todayChange += todayChg;
    // 用 assetCode 去重（空代码用 name 兜底，对每条记录加 hashCode 避免相同名字也被合并）
    final dedupKey =
        h.assetCode.isNotEmpty ? h.assetCode : '__name:${h.assetName}';
    acc.codes.add(dedupKey);

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
      profitLossPercent: acc.totalCost != 0
          ? (acc.totalMV - acc.totalCost) / acc.totalCost * 100
          : 0,
      proportion:
          totalInvestment != 0 ? acc.totalMV / totalInvestment * 100 : 0,
      holdingCount: acc.codes.length,
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

/// 按币种汇总的总资产分布
class CurrencyTotal {
  final String currency;

  /// 该币种下的总市值（原币种数值）
  final double amountInCurrency;

  /// 折算成 CNY 后的金额
  final double amountInCny;
  const CurrencyTotal({
    required this.currency,
    required this.amountInCurrency,
    required this.amountInCny,
  });
}

/// 分币种总资产 Provider：返回按币种聚合的列表，以及合计 CNY
final currencyTotalsProvider = Provider<List<CurrencyTotal>>((ref) {
  final holdings = ref.watch(allHoldingsProvider).valueOrNull ?? [];
  final marketData = ref.watch(marketDataProvider);
  final ratesAsync = ref.watch(exchangeRatesProvider);
  final rates = ratesAsync.valueOrNull ?? {};
  double getRate(String currency) {
    if (currency.isEmpty || currency == 'CNY') return 1.0;
    return rates[currency] ?? ExchangeRateService.getFallbackRate(currency);
  }

  final byCurrency = <String, double>{};
  for (final h in holdings) {
    if (h.quantity == 0) continue;
    final currency = h.currency.isEmpty ? 'CNY' : h.currency;
    final price = marketData[h.assetCode]?.price ?? h.currentPrice;
    byCurrency[currency] = (byCurrency[currency] ?? 0) + h.quantity * price;
  }

  // 按 CNY 等值降序
  final list = byCurrency.entries.map((e) {
    final rate = getRate(e.key);
    return CurrencyTotal(
      currency: e.key,
      amountInCurrency: e.value,
      amountInCny: e.value * rate,
    );
  }).toList()
    ..sort((a, b) => b.amountInCny.compareTo(a.amountInCny));
  return list;
});

/// 按成员的资产汇总 — 监听 allHoldingsProvider 确保持仓变化后自动更新
final memberAssetProvider = Provider.family<double, String>((ref, memberId) {
  final allHoldings = ref.watch(allHoldingsProvider).valueOrNull ?? [];
  final accounts = ref.watch(allAccountsProvider).valueOrNull ?? [];
  final marketData = ref.watch(marketDataProvider);
  final ratesAsync = ref.watch(exchangeRatesProvider);

  // 找出该成员的所有账户 ID
  final memberAccountIds =
      accounts.where((a) => a.memberId == memberId).map((a) => a.id).toSet();

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
  final Set<String> codes = <String>{};
}
