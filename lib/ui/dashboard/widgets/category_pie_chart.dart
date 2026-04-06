import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/asset_summary_model.dart';

class CategoryPieChart extends StatelessWidget {
  final List<AssetSummaryModel> categories;

  const CategoryPieChart({super.key, required this.categories});

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('暂无资产数据', style: TextStyle(color: AppColors.textHint))),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('资产分类', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 340;
                if (isNarrow) {
                  // 窄屏：饼图在上，图例在下
                  return Column(
                    children: [
                      SizedBox(
                        height: 180,
                        child: _buildPieChart(),
                      ),
                      const SizedBox(height: 12),
                      _buildLegend(),
                    ],
                  );
                }
                // 宽屏：饼图和图例并排
                return SizedBox(
                  height: 200,
                  child: Row(
                    children: [
                      Expanded(child: _buildPieChart()),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 150,
                        child: _buildLegend(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart() {
    return PieChart(
      PieChartData(
        centerSpaceRadius: 36,
        sectionsSpace: 2,
        sections: categories.asMap().entries.map((e) {
          final i = e.key;
          final c = e.value;
          final showTitle = c.proportion >= 6; // 占比 < 6% 不显示文字
          return PieChartSectionData(
            color: AppColors.getCategoryColor(i),
            value: c.totalMarketValue,
            title: showTitle ? '${c.proportion.toStringAsFixed(0)}%' : '',
            titleStyle: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            radius: 46,
            titlePositionPercentageOffset: 0.55,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLegend() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: categories.take(8).toList().asMap().entries.map((e) {
        final i = e.key;
        final c = e.value;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.getCategoryColor(i),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  c.categoryName,
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                FormatUtils.formatCurrency(c.totalMarketValue),
                style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
