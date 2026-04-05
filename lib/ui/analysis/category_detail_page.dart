import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format_utils.dart';
import '../../providers/holding_provider.dart';

class CategoryDetailPage extends ConsumerWidget {
  final String categoryType;
  const CategoryDetailPage({super.key, required this.categoryType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdingsAsync = ref.watch(allHoldingsProvider);
    final type = AssetType.values.firstWhere((e) => e.name == categoryType, orElse: () => AssetType.other);

    return Scaffold(
      appBar: AppBar(title: Text(type.label)),
      body: holdingsAsync.when(
        data: (all) {
          final filtered = all.where((h) => h.assetType == categoryType).toList();
          if (filtered.isEmpty) return const Center(child: Text('该分类暂无持仓'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final h = filtered[index];
              final mv = h.quantity * h.currentPrice;
              final pnl = (h.currentPrice - h.costPrice) * h.quantity;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(h.assetName, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(h.assetCode, style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(FormatUtils.formatFullCurrency(mv), style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(FormatUtils.formatChange(pnl),
                            style: TextStyle(fontSize: 12, color: pnl >= 0 ? AppColors.gain : AppColors.loss)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}
