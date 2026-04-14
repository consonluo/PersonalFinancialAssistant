import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/database/app_database.dart';
import '../../../providers/snapshot_provider.dart';

class MiniTrendChart extends ConsumerWidget {
  const MiniTrendChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotsAsync = ref.watch(snapshotListProvider);

    return snapshotsAsync.when(
      data: (allSnapshots) {
        if (allSnapshots.length < 2) {
          return const SizedBox.shrink();
        }

        final cutoff = DateTime.now().subtract(const Duration(days: 30));
        final snapshots =
            allSnapshots.where((s) => s.snapshotDate.isAfter(cutoff)).toList();
        if (snapshots.length < 2) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () => context.push('/asset-trend'),
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('资产走势',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(
                        '${DateFormat('M/d').format(snapshots.first.snapshotDate)} - ${DateFormat('M/d').format(snapshots.last.snapshotDate)}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textHint),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right,
                          size: 16, color: AppColors.textHint),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: _buildChart(snapshots),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildChart(List<AssetSnapshot> snapshots) {
    final spots = snapshots.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.totalAssets);
    }).toList();

    final values = spots.map((s) => s.y).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final range = maxY - minY;
    final padding = range > 0 ? range * 0.15 : (maxY.abs() * 0.15).clamp(1.0, double.infinity);

    final isUp = spots.last.y >= spots.first.y;
    final color = isUp ? AppColors.gain : AppColors.loss;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minY: minY - padding,
        maxY: maxY + padding,
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }
}
