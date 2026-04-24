import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/category_group.dart';
import '../../providers/holding_provider.dart';
import '../../providers/market_provider.dart';
import '../../providers/asset_summary_provider.dart';
import '../../providers/liability_provider.dart';
import '../../data/database/app_database.dart';
import '../../data/models/market_data_model.dart';
import '../../data/models/asset_summary_model.dart';

class TotalAssetsPage extends ConsumerWidget {
  const TotalAssetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(assetSummaryProvider);
    final holdingsAsync = ref.watch(allHoldingsProvider);
    final marketData = ref.watch(marketDataProvider);
    final liabilities = ref.watch(allLiabilitiesProvider).valueOrNull ?? [];
    final totalLiability = liabilities.fold(0.0, (s, l) => s + l.remainingAmount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('资产总览'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: holdingsAsync.when(
        data: (holdings) {
          final grouped = _groupHoldings(holdings, marketData);
          return CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _OverviewHeader(
              totalAssets: overview.totalAssets,
              totalLiability: totalLiability,
              todayChange: overview.todayChange,
              todayChangePct: overview.todayChangePercent,
            )),
            ...grouped.entries.expand((entry) => [
              SliverToBoxAdapter(child: _GroupHeader(group: entry.key, items: entry.value)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _AssetRow(item: entry.value[i]),
                    childCount: entry.value.length,
                  ),
                ),
              ),
            ]),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }

  Map<CategoryGroup, List<_AssetItem>> _groupHoldings(
    List<Holding> holdings,
    Map<String, MarketDataModel> marketData,
  ) {
    final map = <CategoryGroup, List<_AssetItem>>{};

    for (final h in holdings) {
      if (h.quantity == 0) continue;
      final type = AssetType.values.firstWhere((e) => e.name == h.assetType, orElse: () => AssetType.other);
      final group = getGroupForAssetType(type) ?? CategoryGroup.otherAssets;
      final market = marketData[h.assetCode];
      final price = market?.price ?? h.currentPrice;
      final mv = h.quantity * price;
      final cost = h.quantity * h.costPrice;

      map.putIfAbsent(group, () => []);
      map[group]!.add(_AssetItem(
        name: h.assetName,
        code: h.assetCode,
        assetType: type,
        quantity: h.quantity,
        costPrice: h.costPrice,
        currentPrice: price,
        marketValue: mv,
        cost: cost,
        profit: mv - cost,
        profitPct: h.costPrice > 0 ? (price - h.costPrice) / h.costPrice * 100 : 0,
        todayChangePct: market?.changePercent ?? 0,
        todayChange: market != null ? mv * (market.changePercent) / 100 : 0,
      ));
    }

    for (final list in map.values) {
      list.sort((a, b) => b.marketValue.compareTo(a.marketValue));
    }

    final sorted = Map.fromEntries(
      map.entries.toList()..sort((a, b) {
        final aMv = a.value.fold(0.0, (s, v) => s + v.marketValue);
        final bMv = b.value.fold(0.0, (s, v) => s + v.marketValue);
        return bMv.compareTo(aMv);
      }),
    );
    return sorted;
  }
}

class _AssetItem {
  final String name, code;
  final AssetType assetType;
  final double quantity, costPrice, currentPrice, marketValue, cost, profit, profitPct;
  final double todayChangePct, todayChange;

  const _AssetItem({
    required this.name, required this.code, required this.assetType,
    required this.quantity, required this.costPrice, required this.currentPrice,
    required this.marketValue, required this.cost, required this.profit,
    required this.profitPct, required this.todayChangePct, required this.todayChange,
  });
}

class _OverviewHeader extends StatelessWidget {
  final double totalAssets, totalLiability, todayChange, todayChangePct;
  const _OverviewHeader({
    required this.totalAssets, required this.totalLiability,
    required this.todayChange, required this.todayChangePct,
  });

  @override
  Widget build(BuildContext context) {
    final netWorth = totalAssets - totalLiability;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Text('家庭总资产', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
          const SizedBox(height: 6),
          Text(FormatUtils.formatFullCurrency(totalAssets),
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _col('净资产', FormatUtils.formatCurrency(netWorth)),
              Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.3)),
              _col('总负债', FormatUtils.formatCurrency(totalLiability)),
              Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.3)),
              _col('今日', FormatUtils.formatChange(todayChange)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _col(String label, String value) {
    return Column(children: [
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _GroupHeader extends StatelessWidget {
  final CategoryGroup group;
  final List<_AssetItem> items;
  const _GroupHeader({required this.group, required this.items});

  @override
  Widget build(BuildContext context) {
    final totalMv = items.fold(0.0, (s, v) => s + v.marketValue);
    final totalProfit = items.fold(0.0, (s, v) => s + v.profit);
    final totalToday = items.fold(0.0, (s, v) => s + v.todayChange);
    final profitColor = totalProfit >= 0 ? AppColors.gain : AppColors.loss;
    final todayColor = totalToday >= 0 ? AppColors.gain : AppColors.loss;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Icon(group.icon, size: 18, color: group.color),
          const SizedBox(width: 6),
          Text(group.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: group.color)),
          const SizedBox(width: 8),
          Text('${items.length}只', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(FormatUtils.formatCurrency(totalMv), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Row(children: [
                Text('收益 ', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                Text(FormatUtils.formatChange(totalProfit), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: profitColor)),
                Text(' · 今日 ', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                Text(FormatUtils.formatChange(totalToday), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: todayColor)),
              ]),
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
    final profitColor = item.profit > 0 ? AppColors.gain : item.profit < 0 ? AppColors.loss : AppColors.textSecondary;
    final todayColor = item.todayChangePct > 0 ? AppColors.gain : item.todayChangePct < 0 ? AppColors.loss : AppColors.textSecondary;

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
                Text(item.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(item.code, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(FormatUtils.formatCurrency(item.marketValue), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('成本 ${FormatUtils.formatCurrency(item.cost)}', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(FormatUtils.formatPercent(item.todayChangePct), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: todayColor)),
                const SizedBox(height: 2),
                Text(FormatUtils.formatPercent(item.profitPct), style: TextStyle(fontSize: 10, color: profitColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
