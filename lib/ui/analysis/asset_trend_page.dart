import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/snapshot_service.dart';
import '../../data/database/app_database.dart';
import '../../providers/database_provider.dart';

/// 快照数据 Provider
final snapshotListProvider = FutureProvider<List<AssetSnapshot>>((ref) async {
  final db = ref.watch(databaseProvider);
  // 先尝试记录今日快照
  await SnapshotService(db).takeSnapshotIfNeeded();
  return db.getAllSnapshots();
});

class AssetTrendPage extends ConsumerStatefulWidget {
  const AssetTrendPage({super.key});

  @override
  ConsumerState<AssetTrendPage> createState() => _AssetTrendPageState();
}

class _AssetTrendPageState extends ConsumerState<AssetTrendPage> {
  int _selectedRange = 30; // 默认显示30天
  String _selectedMetric = 'totalAssets'; // totalAssets / netWorth / totalLiabilities

  static const _rangeOptions = [
    {'days': 7, 'label': '7天'},
    {'days': 30, 'label': '30天'},
    {'days': 90, 'label': '3月'},
    {'days': 180, 'label': '半年'},
    {'days': 365, 'label': '1年'},
    {'days': -1, 'label': '全部'},
  ];

  static const _metricOptions = [
    {'key': 'totalAssets', 'label': '总资产', 'color': AppColors.primary},
    {'key': 'netWorth', 'label': '净资产', 'color': AppColors.success},
    {'key': 'totalLiabilities', 'label': '总负债', 'color': AppColors.error},
  ];

  @override
  Widget build(BuildContext context) {
    final snapshotsAsync = ref.watch(snapshotListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('资产走势')),
      body: snapshotsAsync.when(
        data: (allSnapshots) {
          if (allSnapshots.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.show_chart, size: 48, color: AppColors.textHint),
                  SizedBox(height: 12),
                  Text('暂无历史数据', style: TextStyle(color: AppColors.textHint, fontSize: 16)),
                  SizedBox(height: 8),
                  Text('每天打开 App 会自动记录资产快照', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
                ],
              ),
            );
          }

          // 按时间范围过滤
          final snapshots = _selectedRange == -1
              ? allSnapshots
              : allSnapshots.where((s) {
                  final cutoff = DateTime.now().subtract(Duration(days: _selectedRange));
                  return s.snapshotDate.isAfter(cutoff);
                }).toList();

          if (snapshots.isEmpty) {
            return const Center(child: Text('所选时间范围内无数据'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 时间范围选择
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _rangeOptions.map((opt) {
                    final days = opt['days'] as int;
                    final selected = _selectedRange == days;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(opt['label'] as String),
                        selected: selected,
                        onSelected: (_) => setState(() => _selectedRange = days),
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : null,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),

              // 指标选择
              Row(
                children: _metricOptions.map((opt) {
                  final key = opt['key'] as String;
                  final selected = _selectedMetric == key;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        onTap: () => setState(() => _selectedMetric = key),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selected ? (opt['color'] as Color).withValues(alpha: 0.15) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected ? (opt['color'] as Color) : AppColors.textHint.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                opt['label'] as String,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: selected ? (opt['color'] as Color) : AppColors.textSecondary,
                                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                FormatUtils.formatCurrency(_getMetricValue(snapshots.last, key)),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: selected ? (opt['color'] as Color) : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // 走势图
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 20, 16, 12),
                  child: SizedBox(
                    height: 240,
                    child: _buildLineChart(snapshots),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 变化统计
              if (snapshots.length >= 2) ...[
                _buildChangeCard(snapshots),
                const SizedBox(height: 16),
              ],

              // 历史记录列表
              const Text('历史记录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...snapshots.reversed.take(30).map((s) {
                final dateStr = DateFormat('MM/dd').format(s.snapshotDate);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(width: 50, child: Text(dateStr, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                      Expanded(child: Text(FormatUtils.formatCurrency(s.totalAssets), style: const TextStyle(fontSize: 13))),
                      Expanded(child: Text(FormatUtils.formatCurrency(s.netWorth), style: const TextStyle(fontSize: 13, color: AppColors.success))),
                      SizedBox(
                        width: 80,
                        child: Text(
                          FormatUtils.formatCurrency(s.totalLiabilities),
                          style: const TextStyle(fontSize: 13, color: AppColors.error),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }

  double _getMetricValue(AssetSnapshot s, String metric) {
    switch (metric) {
      case 'netWorth': return s.netWorth;
      case 'totalLiabilities': return s.totalLiabilities;
      default: return s.totalAssets;
    }
  }

  Color _getMetricColor() {
    switch (_selectedMetric) {
      case 'netWorth': return AppColors.success;
      case 'totalLiabilities': return AppColors.error;
      default: return AppColors.primary;
    }
  }

  Widget _buildLineChart(List<AssetSnapshot> snapshots) {
    if (snapshots.length < 2) {
      return const Center(child: Text('至少需要两天数据才能显示走势图', style: TextStyle(color: AppColors.textHint)));
    }

    final color = _getMetricColor();
    final spots = snapshots.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), _getMetricValue(e.value, _selectedMetric));
    }).toList();

    final values = spots.map((s) => s.y).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.1;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) > 0 ? (maxY - minY) / 4 : 1,
          getDrawingHorizontalLine: (value) => FlLine(
            color: AppColors.textHint.withValues(alpha: 0.15),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              getTitlesWidget: (value, meta) {
                return Text(
                  FormatUtils.formatCurrency(value),
                  style: const TextStyle(fontSize: 10, color: AppColors.textHint),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (snapshots.length / 5).ceilToDouble().clamp(1, double.infinity),
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= snapshots.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat('M/d').format(snapshots[index].snapshotDate),
                    style: const TextStyle(fontSize: 10, color: AppColors.textHint),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: minY - padding,
        maxY: maxY + padding,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 2.5,
            dotData: FlDotData(
              show: snapshots.length <= 30,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 3,
                color: Colors.white,
                strokeWidth: 2,
                strokeColor: color,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.1),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final index = spot.x.toInt();
                final date = index < snapshots.length
                    ? DateFormat('yyyy/MM/dd').format(snapshots[index].snapshotDate)
                    : '';
                return LineTooltipItem(
                  '$date\n${FormatUtils.formatCurrency(spot.y)}',
                  TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildChangeCard(List<AssetSnapshot> snapshots) {
    final latest = snapshots.last;
    final first = snapshots.first;
    final assetChange = latest.totalAssets - first.totalAssets;
    final assetChangePct = first.totalAssets != 0 ? assetChange / first.totalAssets * 100 : 0.0;
    final netChange = latest.netWorth - first.netWorth;
    final netChangePct = first.netWorth != 0 ? netChange / first.netWorth * 100 : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('区间变化', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ChangeItem(
                    label: '总资产变化',
                    value: FormatUtils.formatChange(assetChange),
                    percent: FormatUtils.formatPercent(assetChangePct),
                    isPositive: assetChange >= 0,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _ChangeItem(
                    label: '净资产变化',
                    value: FormatUtils.formatChange(netChange),
                    percent: FormatUtils.formatPercent(netChangePct),
                    isPositive: netChange >= 0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangeItem extends StatelessWidget {
  final String label;
  final String value;
  final String percent;
  final bool isPositive;

  const _ChangeItem({
    required this.label,
    required this.value,
    required this.percent,
    required this.isPositive,
  });

  @override
  Widget build(BuildContext context) {
    final color = isPositive ? AppColors.gain : AppColors.loss;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
        Text(percent, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
