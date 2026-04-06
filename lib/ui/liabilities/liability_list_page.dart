import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format_utils.dart';
import '../../providers/liability_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/sync_provider.dart';

class LiabilityListPage extends ConsumerWidget {
  const LiabilityListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liabilitiesAsync = ref.watch(allLiabilitiesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('负债管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: '截图导入',
            onPressed: () => context.push('/liability-ocr'),
          ),
          IconButton(icon: const Icon(Icons.bar_chart), onPressed: () => context.push('/balance-sheet')),
        ],
      ),
      body: liabilitiesAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.money_off_outlined, size: 48, color: AppColors.textHint),
                  const SizedBox(height: 12),
                  const Text('暂无负债', style: TextStyle(color: AppColors.textHint)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/liability-form'),
                    icon: const Icon(Icons.add),
                    label: const Text('添加负债'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final l = items[index];
              return Dismissible(
                key: ValueKey(l.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmDelete(context, ref, l.id, l.name),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: AppColors.error,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => context.push('/liability-form?id=${l.id}'),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.money_off, color: AppColors.error),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text('${l.type} · 利率 ${l.interestRate}%', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(FormatUtils.formatFullCurrency(l.remainingAmount), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.error)),
                              Text('月供 ${FormatUtils.formatFullCurrency(l.monthlyPayment)}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/liability-form'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, WidgetRef ref, String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除负债'),
        content: Text('确定删除「$name」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final db = ref.read(databaseProvider);
      await db.deleteLiability(id);
      ref.read(autoSyncProvider).triggerAutoSync();
      return true;
    }
    return false;
  }
}
