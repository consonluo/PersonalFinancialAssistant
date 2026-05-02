import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/category_group.dart';
import '../../core/utils/exchange_rate_service.dart';
import '../../providers/holding_provider.dart';
import '../../providers/market_provider.dart';
import '../../providers/asset_summary_provider.dart';
import '../../providers/liability_provider.dart';
import '../../data/database/app_database.dart';
import '../../data/models/market_data_model.dart';

class TotalAssetsPage extends ConsumerWidget {
  const TotalAssetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(assetSummaryProvider);
    final holdingsAsync = ref.watch(allHoldingsProvider);
    final marketData = ref.watch(marketDataProvider);
    final totalLiability = ref.watch(totalLiabilityProvider);
    final ratesAsync = ref.watch(exchangeRatesProvider);
    final rates = ratesAsync.valueOrNull ?? {};
    final currencyTotals = ref.watch(currencyTotalsProvider);
    final netCurrencyTotals = ref.watch(netCurrencyTotalsProvider);
    double getRate(String currency) {
      if (currency.isEmpty || currency == 'CNY') return 1.0;
      return rates[currency] ?? ExchangeRateService.getFallbackRate(currency);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('资产总览'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: holdingsAsync.when(
        data: (holdings) {
          final grouped = _groupHoldings(holdings, marketData, getRate);
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _OverviewHeader(
                  totalAssets: overview.totalAssets,
                  totalLiability: totalLiability,
                  todayChange: overview.todayChange,
                  todayChangePct: overview.todayChangePercent,
                  currencyTotals: currencyTotals,
                  netCurrencyTotals: netCurrencyTotals,
                ),
              ),
              ...grouped.entries.expand(
                (entry) => [
                  SliverToBoxAdapter(
                    child: _GroupHeader(group: entry.key, items: entry.value),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _AssetRow(item: entry.value[i]),
                        childCount: entry.value.length,
                      ),
                    ),
                  ),
                ],
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }

  /// 按 assetCode 跨账户合并相同资产，并按大类分组
  /// 明细行金额用原币展示；marketValueCny / costCny 用于分组小计
  Map<CategoryGroup, List<_AssetItem>> _groupHoldings(
    List<Holding> holdings,
    Map<String, MarketDataModel> marketData,
    double Function(String) getRate,
  ) {
    // 第一步：按 assetCode 合并
    final agg = <String, _Acc>{};
    for (final h in holdings) {
      if (h.quantity == 0) continue;
      final key =
          h.assetCode.isNotEmpty ? h.assetCode : '__name:${h.assetName}';
      final mkt = marketData[h.assetCode];
      final price = mkt?.price ?? h.currentPrice;
      agg.putIfAbsent(
        key,
        () => _Acc(
          name: h.assetName,
          code: h.assetCode,
          type: h.assetType,
          currency: h.currency.isEmpty ? 'CNY' : h.currency,
          price: price,
          changePct: mkt?.changePercent ?? 0,
        ),
      );
      final a = agg[key]!;
      a.qty += h.quantity;
      a.totalCost += h.quantity * h.costPrice;
      a.price = price;
      if (mkt != null) a.changePct = mkt.changePercent;
    }

    final map = <CategoryGroup, List<_AssetItem>>{};
    for (final a in agg.values) {
      final type = AssetType.values.firstWhere(
        (e) => e.name == a.type,
        orElse: () => AssetType.other,
      );
      final group = getGroupForAssetType(type) ?? CategoryGroup.otherAssets;
      final mv = a.qty * a.price;
      final cost = a.totalCost;
      final rate = getRate(a.currency);
      map.putIfAbsent(group, () => []);
      map[group]!.add(
        _AssetItem(
          name: a.name,
          code: a.code,
          assetType: type,
          currency: a.currency,
          quantity: a.qty,
          costPrice: a.qty != 0 ? cost / a.qty : 0,
          currentPrice: a.price,
          marketValue: mv,
          cost: cost,
          profit: mv - cost,
          profitPct: cost > 0 ? (mv - cost) / cost * 100 : 0,
          todayChangePct: a.changePct,
          todayChange: mv * a.changePct / 100,
          marketValueCny: mv * rate,
          costCny: cost * rate,
          profitCny: (mv - cost) * rate,
          todayChangeCny: mv * a.changePct / 100 * rate,
        ),
      );
    }

    for (final list in map.values) {
      list.sort((a, b) => b.marketValueCny.compareTo(a.marketValueCny));
    }

    final sorted = Map.fromEntries(
      map.entries.toList()..sort((a, b) {
        final aMv = a.value.fold(0.0, (s, v) => s + v.marketValueCny);
        final bMv = b.value.fold(0.0, (s, v) => s + v.marketValueCny);
        return bMv.compareTo(aMv);
      }),
    );
    return sorted;
  }
}

/// 用于按 assetCode 合并的临时累加结构
class _Acc {
  String name, code, type, currency;
  double qty = 0, totalCost = 0, price, changePct;
  _Acc({
    required this.name,
    required this.code,
    required this.type,
    required this.currency,
    required this.price,
    required this.changePct,
  });
}

class _AssetItem {
  final String name, code;
  final AssetType assetType;
  final String currency;
  // 原币种数值（用于明细行展示）
  final double quantity,
      costPrice,
      currentPrice,
      marketValue,
      cost,
      profit,
      profitPct;
  final double todayChangePct, todayChange;
  // 折算 CNY 数值（用于分组小计/排序）
  final double marketValueCny, costCny, profitCny, todayChangeCny;

  const _AssetItem({
    required this.name,
    required this.code,
    required this.assetType,
    required this.currency,
    required this.quantity,
    required this.costPrice,
    required this.currentPrice,
    required this.marketValue,
    required this.cost,
    required this.profit,
    required this.profitPct,
    required this.todayChangePct,
    required this.todayChange,
    required this.marketValueCny,
    required this.costCny,
    required this.profitCny,
    required this.todayChangeCny,
  });
}

class _OverviewHeader extends StatelessWidget {
  final double totalAssets, totalLiability, todayChange, todayChangePct;
  final List<CurrencyTotal> currencyTotals;
  final List<CurrencyNetTotal> netCurrencyTotals;
  const _OverviewHeader({
    required this.totalAssets,
    required this.totalLiability,
    required this.todayChange,
    required this.todayChangePct,
    required this.currencyTotals,
    required this.netCurrencyTotals,
  });

  @override
  Widget build(BuildContext context) {
    final netWorth = totalAssets - totalLiability;
    final hasMultiCurrency = currencyTotals.any(
      (c) => c.currency != 'CNY' && c.amountInCurrency > 0,
    );
    final hasNetBreakdown = netCurrencyTotals.any(
      (c) => c.netInCurrency.abs() > 0.0001,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            '家庭总资产 (折合人民币)',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            FormatUtils.formatFullCurrency(totalAssets),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hasMultiCurrency) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                children:
                    currencyTotals
                        .where((c) => c.amountInCurrency > 0)
                        .map(
                          (c) => _CurrencyChip(
                            currency: c.currency,
                            amount: c.amountInCurrency,
                          ),
                        )
                        .toList(),
              ),
            ),
          ],
          if (hasNetBreakdown) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                children:
                    netCurrencyTotals
                        .where((c) => c.netInCurrency.abs() > 0.0001)
                        .map(
                          (c) => Text(
                            '${c.currency}净值 ${FormatUtils.formatCurrency(c.netInCurrency, currency: c.currency)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                        .toList(),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _col('净资产', FormatUtils.formatCurrency(netWorth)),
              Container(
                width: 1,
                height: 28,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              _col('总负债', FormatUtils.formatCurrency(totalLiability)),
              Container(
                width: 1,
                height: 28,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              _col('今日', FormatUtils.formatChange(todayChange)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _col(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CurrencyChip extends StatelessWidget {
  final String currency;
  final double amount;
  const _CurrencyChip({required this.currency, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          currency,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          FormatUtils.formatCurrency(amount, currency: currency),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final CategoryGroup group;
  final List<_AssetItem> items;
  const _GroupHeader({required this.group, required this.items});

  @override
  Widget build(BuildContext context) {
    // 分组小计统一用 CNY 折算（避免不同币种相加无意义）
    final totalMv = items.fold(0.0, (s, v) => s + v.marketValueCny);
    final totalProfit = items.fold(0.0, (s, v) => s + v.profitCny);
    final totalToday = items.fold(0.0, (s, v) => s + v.todayChangeCny);
    final profitColor = totalProfit >= 0 ? AppColors.gain : AppColors.loss;
    final todayColor = totalToday >= 0 ? AppColors.gain : AppColors.loss;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Icon(group.icon, size: 18, color: group.color),
          const SizedBox(width: 6),
          Text(
            group.label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: group.color,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${items.length}只',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                FormatUtils.formatCurrency(totalMv),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  Text(
                    '收益 ',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    FormatUtils.formatChange(totalProfit),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: profitColor,
                    ),
                  ),
                  Text(
                    ' · 今日 ',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    FormatUtils.formatChange(totalToday),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: todayColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  final _AssetItem item;
  const _AssetRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final profitColor =
        item.profit > 0
            ? AppColors.gain
            : item.profit < 0
            ? AppColors.loss
            : AppColors.textSecondary;
    final todayColor =
        item.todayChangePct > 0
            ? AppColors.gain
            : item.todayChangePct < 0
            ? AppColors.loss
            : AppColors.textSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.backgroundCard),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  item.code,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  FormatUtils.formatCurrency(
                    item.marketValue,
                    currency: item.currency,
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '成本 ${FormatUtils.formatCurrency(item.cost, currency: item.currency)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  FormatUtils.formatPercent(item.todayChangePct),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: todayColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  FormatUtils.formatPercent(item.profitPct),
                  style: TextStyle(fontSize: 10, color: profitColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
