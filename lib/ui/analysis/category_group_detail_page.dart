import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/category_group.dart';
import '../../providers/holding_provider.dart';
import '../../providers/market_provider.dart';

class CategoryGroupDetailPage extends ConsumerWidget {
  final String groupName;
  const CategoryGroupDetailPage({super.key, required this.groupName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group =
        CategoryGroup.values.where((g) => g.name == groupName).firstOrNull;
    if (group == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('未知分类')),
        body: const Center(child: Text('分类不存在')),
      );
    }

    final assetTypes = getAssetTypesForGroup(group);
    final typeNames = assetTypes.map((t) => t.name).toSet();
    final holdingsAsync = ref.watch(allHoldingsProvider);
    final marketData = ref.watch(marketDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(group.label),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: holdingsAsync.when(
            data: (all) {
              final filtered =
                  all.where((h) => typeNames.contains(h.assetType)).toList();
              if (filtered.isEmpty) return const Center(child: Text('该分类暂无持仓'));

              // 按 assetCode 跨账户合并，避免同一标的重复展示
              final merged = <String, _MergedCategoryHolding>{};
              for (final h in filtered) {
                if (h.quantity == 0) continue;
                final market = marketData[h.assetCode];
                final price = market?.price ?? h.currentPrice;
                final key = h.assetCode.isNotEmpty
                    ? h.assetCode
                    : '__name:${h.assetName}';
                final m = merged.putIfAbsent(
                  key,
                  () => _MergedCategoryHolding(
                    assetName: h.assetName,
                    assetCode: h.assetCode,
                    assetType: h.assetType,
                    quantity: 0,
                    totalCost: 0,
                    currentPrice: price,
                    todayChgPct: market?.changePercent ?? 0.0,
                  ),
                );
                m.quantity += h.quantity;
                m.totalCost += h.quantity * h.costPrice;
                m.currentPrice = price;
                if (market != null) m.todayChgPct = market.changePercent;
              }
              final mergedList = merged.values.toList()
                ..sort((a, b) {
                  final aMv = a.quantity * a.currentPrice;
                  final bMv = b.quantity * b.currentPrice;
                  return bMv.compareTo(aMv);
                });

              double totalMv = 0, totalPnl = 0;
              for (final h in mergedList) {
                final mv = h.quantity * h.currentPrice;
                totalMv += mv;
                totalPnl += mv - h.totalCost;
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SummaryCard(
                    group: group,
                    totalMv: totalMv,
                    totalPnl: totalPnl,
                    count: mergedList.length,
                  ),
                  const SizedBox(height: 12),
                  ...mergedList.map((h) {
                    final mv = h.quantity * h.currentPrice;
                    final cost = h.totalCost;
                    final pnl = mv - cost;
                    final pnlPct = cost != 0 ? pnl / cost * 100 : 0.0;
                    final assetType = AssetType.values
                        .where((e) => e.name == h.assetType)
                        .firstOrNull;
                    final dm = getDisplayModeForAssetType(
                      assetType ?? AssetType.other,
                    );

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                if (assetType != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: group.color.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      assetType.code,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: group.color,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        h.assetName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (h.assetCode.isNotEmpty &&
                                          h.assetCode != 'DEPOSIT' &&
                                          h.assetCode != 'WEALTH' &&
                                          h.assetCode != 'unknown')
                                        Text(
                                          h.assetCode,
                                          style: const TextStyle(
                                            color: AppColors.textHint,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      FormatUtils.formatFullCurrency(mv),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                    if (dm != HoldingDisplayMode.deposit)
                                      Text(
                                        '${pnl >= 0 ? "+" : ""}${FormatUtils.formatCurrency(pnl)} (${FormatUtils.formatPercent(pnlPct)})',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: pnl >= 0
                                              ? AppColors.gain
                                              : AppColors.loss,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            if (dm == HoldingDisplayMode.tradable) ...[
                              const Divider(height: 16),
                              Row(
                                children: [
                                  _InfoItem(
                                    label: '数量',
                                    value: FormatUtils.formatNumber(h.quantity),
                                  ),
                                  _InfoItem(
                                    label: '现价',
                                    value:
                                        FormatUtils.formatPrice(h.currentPrice),
                                  ),
                                  _InfoItem(
                                    label: '成本',
                                    value: FormatUtils.formatPrice(
                                      h.quantity != 0
                                          ? h.totalCost / h.quantity
                                          : 0,
                                    ),
                                  ),
                                  _InfoItem(
                                    label: '今日',
                                    value:
                                        '${h.todayChgPct >= 0 ? "+" : ""}${h.todayChgPct.toStringAsFixed(2)}%',
                                    color: h.todayChgPct >= 0
                                        ? AppColors.gain
                                        : AppColors.loss,
                                  ),
                                ],
                              ),
                            ] else if (dm ==
                                HoldingDisplayMode.fixedIncome) ...[
                              const Divider(height: 16),
                              Row(
                                children: [
                                  _InfoItem(
                                    label: '份额',
                                    value: h.quantity > 1
                                        ? FormatUtils.formatNumber(h.quantity)
                                        : '-',
                                  ),
                                  _InfoItem(
                                    label: '净值',
                                    value: h.currentPrice < 100
                                        ? h.currentPrice.toStringAsFixed(4)
                                        : FormatUtils.formatPrice(
                                            h.currentPrice),
                                  ),
                                  _InfoItem(
                                    label: '成本',
                                    value: FormatUtils.formatCurrency(cost),
                                  ),
                                  _InfoItem(
                                    label: '收益',
                                    value: FormatUtils.formatChange(pnl),
                                    color: pnl >= 0
                                        ? AppColors.gain
                                        : AppColors.loss,
                                  ),
                                ],
                              ),
                            ] else if (dm == HoldingDisplayMode.wealth) ...[
                              const Divider(height: 16),
                              Row(
                                children: [
                                  _InfoItem(
                                    label: '投入成本',
                                    value: FormatUtils.formatCurrency(cost),
                                  ),
                                  _InfoItem(
                                    label: '累计收益',
                                    value: FormatUtils.formatChange(pnl),
                                    color: pnl >= 0
                                        ? AppColors.gain
                                        : AppColors.loss,
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
          ),
        ),
      ),
    );
  }
}

class _MergedCategoryHolding {
  String assetName;
  String assetCode;
  String assetType;
  double quantity;
  double totalCost;
  double currentPrice;
  double todayChgPct;
  _MergedCategoryHolding({
    required this.assetName,
    required this.assetCode,
    required this.assetType,
    required this.quantity,
    required this.totalCost,
    required this.currentPrice,
    required this.todayChgPct,
  });
}

class _SummaryCard extends StatelessWidget {
  final CategoryGroup group;
  final double totalMv;
  final double totalPnl;
  final int count;
  const _SummaryCard(
      {required this.group,
      required this.totalMv,
      required this.totalPnl,
      required this.count});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: group.color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(group.icon, color: group.color, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.label,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: group.color)),
                  const SizedBox(height: 4),
                  Text(FormatUtils.formatCurrency(totalMv),
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$count 笔',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  '盈亏 ${totalPnl >= 0 ? "+" : ""}${FormatUtils.formatCurrency(totalPnl)}',
                  style: TextStyle(
                      fontSize: 13,
                      color: totalPnl >= 0 ? AppColors.gain : AppColors.loss,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _InfoItem({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}
