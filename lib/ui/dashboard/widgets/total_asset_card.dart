import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';

class TotalAssetCard extends StatelessWidget {
  final double totalAssets;
  final double netWorth;
  final double todayChange;
  final double todayChangePercent;
  final VoidCallback? onTapTotal;
  final VoidCallback? onTapToday;

  const TotalAssetCard({
    super.key,
    required this.totalAssets,
    required this.netWorth,
    required this.todayChange,
    required this.todayChangePercent,
    this.onTapTotal,
    this.onTapToday,
  });

  @override
  Widget build(BuildContext context) {
    final isUp = todayChange >= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onTapTotal,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('家庭总资产', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14)),
                  if (onTapTotal != null) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 16, color: Colors.white.withValues(alpha: 0.5)),
                  ],
                ]),
                const SizedBox(height: 8),
                Text(
                  FormatUtils.formatFullCurrency(totalAssets),
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onTapToday,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (isUp ? Colors.red : Colors.green).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isUp ? Icons.trending_up : Icons.trending_down, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '今日 ${FormatUtils.formatChange(todayChange)} (${FormatUtils.formatPercent(todayChangePercent)})',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onTapToday != null) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 14, color: Colors.white.withValues(alpha: 0.6)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
