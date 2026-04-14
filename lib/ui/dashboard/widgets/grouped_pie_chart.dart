import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/category_group.dart';

class GroupedPieChart extends StatelessWidget {
  final List<GroupedCategoryData> grouped;
  const GroupedPieChart({super.key, required this.grouped});

  @override
  Widget build(BuildContext context) {
    if (grouped.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('资产分布',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 340;
              if (isNarrow) {
                return Column(
                  children: [
                    SizedBox(height: 160, child: _buildPie(context)),
                    const SizedBox(height: 12),
                    _buildLegend(context),
                  ],
                );
              }
              return SizedBox(
                height: 180,
                child: Row(
                  children: [
                    Expanded(child: _buildPie(context)),
                    const SizedBox(width: 12),
                    SizedBox(width: 160, child: _buildLegend(context)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPie(BuildContext context) {
    return PieChart(
      PieChartData(
        centerSpaceRadius: 32,
        sectionsSpace: 2,
        pieTouchData: PieTouchData(
          touchCallback: (event, response) {
            if (event is FlTapUpEvent && response?.touchedSection != null) {
              final idx = response!.touchedSection!.touchedSectionIndex;
              if (idx >= 0 && idx < grouped.length) {
                context.push('/analysis/category-group/${grouped[idx].group.name}');
              }
            }
          },
        ),
        sections: grouped.asMap().entries.map((e) {
          final g = e.value;
          final showTitle = g.proportion >= 8;
          return PieChartSectionData(
            color: g.group.color,
            value: g.totalMarketValue.abs().clamp(0.01, double.infinity),
            title: showTitle ? '${g.proportion.toStringAsFixed(0)}%' : '',
            titleStyle: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600),
            radius: 44,
            titlePositionPercentageOffset: 0.55,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLegend(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: grouped.map((g) {
        return InkWell(
          onTap: () =>
              context.push('/analysis/category-group/${g.group.name}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: g.group.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(g.group.label,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
                Text(FormatUtils.formatCurrency(g.totalMarketValue),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
