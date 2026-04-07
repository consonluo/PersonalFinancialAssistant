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
    final group = CategoryGroup.values.where((g) => g.name == groupName).firstOrNull;
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
          final filtered = all.where((h) => typeNames.contains(h.assetType)).toList();
          if (filtered.isEmpty) return const Center(child: Text('该分类暂无持仓'));

          double totalMv = 0, totalPnl = 0;
          for (final h in filtered) {
            final market = marketData[h.assetCode];
            final price = market?.price ?? h.currentPrice;
            totalMv += h.quantity * price;
            totalPnl += (price - h.costPrice) * h.quantity;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SummaryCard(
                group: group,
                totalMv: totalMv,
                totalPnl: totalPnl,
                count: filtered.length,
              ),
              const SizedBox(height: 12),
              ...filtered.map((h) {
                final market = marketData[h.assetCode];
                final price = market?.price ?? h.currentPrice;
                final mv = h.quantity * price;
                final pnl = (price - h.costPrice) * h.quantity;
                final pnlPct = h.costPrice != 0 ? (price - h.costPrice) / h.costPrice * 100 : 0.0;
                final todayChg = market != null ? mv * market.changePercent / 100 : 0.0;
                final todayChgPct = market?.changePercent ?? 0.0;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(h.assetName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                  const SizedBox(height: 2),
                                  Text(h.assetCode, style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(FormatUtils.formatFullCurrency(mv), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                Text(
                                  '${pnl >= 0 ? "+" : ""}${FormatUtils.formatFullCurrency(pnl)} (${FormatUtils.formatPercent(pnlPct)})',
                                  style: TextStyle(fontSize: 12, color: pnl >= 0 ? AppColors.gain : AppColors.loss),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Divider(height: 16),
                        Row(
                          children: [
                            _InfoItem(label: '数量', value: FormatUtils.formatNumber(h.quantity)),
                            _InfoItem(label: '现价', value: FormatUtils.formatPrice(price)),
                            _InfoItem(label: '成本', value: FormatUtils.formatPrice(h.costPrice)),
                            _InfoItem(
                              label: '今日',
                              value: '${todayChgPct >= 0 ? "+" : ""}${todayChgPct.toStringAsFixed(2)}%',
                              color: todayChgPct >= 0 ? AppColors.gain : AppColors.loss,
                            ),
                          ],
                        ),
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

class _SummaryCard extends StatelessWidget {
  final CategoryGroup group;
  final double totalMv;
  final double totalPnl;
  final int count;
  const _SummaryCard({required this.group, required this.totalMv, required this.totalPnl, required this.count});

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
                  Text(group.label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: group.color)),
                  const SizedBox(height: 4),
                  Text(FormatUtils.formatCurrency(totalMv), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$count 只', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  '盈亏 ${totalPnl >= 0 ? "+" : ""}${FormatUtils.formatCurrency(totalPnl)}',
                  style: TextStyle(fontSize: 13, color: totalPnl >= 0 ? AppColors.gain : AppColors.loss, fontWeight: FontWeight.w600),
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
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}
