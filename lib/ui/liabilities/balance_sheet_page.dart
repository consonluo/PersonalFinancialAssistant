import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format_utils.dart';
import '../../providers/asset_summary_provider.dart';
import '../../providers/liability_provider.dart';

class BalanceSheetPage extends ConsumerWidget {
  const BalanceSheetPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(assetSummaryProvider);
    final totalLiability = ref.watch(totalLiabilityProvider);
    final netWorth = overview.totalAssets - totalLiability;

    return Scaffold(
      appBar: AppBar(title: const Text('资产负债表')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader('净资产', FormatUtils.formatFullCurrency(netWorth), netWorth >= 0 ? AppColors.success : AppColors.error),
          const SizedBox(height: 16),
          _SectionHeader('总资产', FormatUtils.formatFullCurrency(overview.totalAssets), AppColors.primary),
          ...overview.categories.map((c) => _ItemRow(c.categoryName, FormatUtils.formatFullCurrency(c.totalMarketValue))),
          const Divider(height: 24),
          _SectionHeader('总负债', FormatUtils.formatFullCurrency(totalLiability), AppColors.error),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SectionHeader(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final String label;
  final String value;
  const _ItemRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
