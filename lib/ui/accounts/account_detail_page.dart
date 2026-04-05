import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format_utils.dart';
import '../../providers/account_provider.dart';
import '../../providers/holding_provider.dart';

class AccountDetailPage extends ConsumerWidget {
  final String accountId;
  const AccountDetailPage({super.key, required this.accountId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(accountByIdProvider(accountId));
    final holdingsAsync = ref.watch(holdingsByAccountProvider(accountId));

    return Scaffold(
      appBar: AppBar(
        title: accountAsync.whenOrNull(data: (a) => Text(a?.name ?? '')) ?? const Text('账户详情'),
      ),
      body: holdingsAsync.when(
        data: (holdings) {
          if (holdings.isEmpty) return const Center(child: Text('暂无持仓'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: holdings.length,
            itemBuilder: (context, index) {
              final h = holdings[index];
              final mv = h.quantity * h.currentPrice;
              final pnl = (h.currentPrice - h.costPrice) * h.quantity;
              final pnlPct = h.costPrice != 0 ? (h.currentPrice - h.costPrice) / h.costPrice * 100 : 0.0;
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
                          Text(
                            FormatUtils.formatPercent(pnlPct),
                            style: TextStyle(
                              color: pnl >= 0 ? AppColors.gain : AppColors.loss,
                              fontSize: 12,
                            ),
                          ),
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'ocr',
            onPressed: () => context.push('/ocr-import?accountId=$accountId'),
            child: const Icon(Icons.camera_alt),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'add',
            onPressed: () => context.push('/holding-form?accountId=$accountId'),
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
