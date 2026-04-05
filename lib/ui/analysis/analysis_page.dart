import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format_utils.dart';
import '../../providers/asset_summary_provider.dart';

class AnalysisPage extends ConsumerWidget {
  const AnalysisPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(assetSummaryProvider);
    final categories = overview.categories;

    return Scaffold(
      appBar: AppBar(title: const Text('资产分析')),
      body: categories.isEmpty
          ? const Center(child: Text('暂无数据'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 汇总统计
                SizedBox(
                  height: 80,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _StatChip(label: '投资总额', value: FormatUtils.formatCurrency(overview.totalInvestment), color: AppColors.primary),
                      _StatChip(label: '今日收益', value: FormatUtils.formatChange(overview.todayChange), color: overview.todayChange >= 0 ? AppColors.gain : AppColors.loss),
                      _StatChip(label: '分类数', value: '${categories.length}', color: AppColors.info),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 资产走势入口
                Card(
                  child: InkWell(
                    onTap: () => context.push('/asset-trend'),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.show_chart, color: AppColors.success),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('资产走势图', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                Text('查看资产历史变化趋势', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: AppColors.textHint),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...categories.asMap().entries.map((e) {
                  final i = e.key;
                  final c = e.value;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => context.push('/analysis/category/${c.assetType.name}'),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 12, height: 12,
                              decoration: BoxDecoration(color: AppColors.getCategoryColor(i), shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.categoryName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  LinearProgressIndicator(
                                    value: c.proportion / 100,
                                    backgroundColor: AppColors.backgroundCard,
                                    color: AppColors.getCategoryColor(i),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('${c.holdingCount}只  占比 ${c.proportion.toStringAsFixed(1)}%',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(FormatUtils.formatCurrency(c.totalMarketValue),
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(FormatUtils.formatPercent(c.profitLossPercent),
                                  style: TextStyle(fontSize: 12, color: c.profitLoss >= 0 ? AppColors.gain : AppColors.loss)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.7)]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
