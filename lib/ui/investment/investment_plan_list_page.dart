import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/format_utils.dart';
import '../../providers/investment_plan_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/sync_provider.dart';

class InvestmentPlanListPage extends ConsumerWidget {
  const InvestmentPlanListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(allInvestmentPlansProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('定投计划'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: '截图导入',
            onPressed: () => context.push('/investment-plan-ocr'),
          ),
        ],
      ),
      body: plansAsync.when(
        data: (plans) {
          if (plans.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event_repeat, size: 48, color: AppColors.textHint),
                  const SizedBox(height: 12),
                  const Text('暂无定投计划', style: TextStyle(color: AppColors.textHint, fontSize: 16)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/investment-plan-form'),
                    icon: const Icon(Icons.add),
                    label: const Text('创建定投计划'),
                  ),
                ],
              ),
            );
          }

          // 统计
          final activePlans = plans.where((p) => p.isActive).toList();
          final totalMonthly = activePlans.fold(0.0, (sum, p) {
            final freq = InvestFrequency.values.firstWhere((f) => f.name == p.frequency, orElse: () => InvestFrequency.monthly);
            switch (freq) {
              case InvestFrequency.daily: return sum + p.amount * 22;
              case InvestFrequency.weekly: return sum + p.amount * 4.3;
              case InvestFrequency.biweekly: return sum + p.amount * 2.15;
              case InvestFrequency.monthly: return sum + p.amount;
            }
          });

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 汇总卡片
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('活跃计划', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                            Text('${activePlans.length} 个', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('预计月投入', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                            Text(FormatUtils.formatCurrency(totalMonthly), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.info)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              ...plans.map((p) {
                final freq = InvestFrequency.values.firstWhere((f) => f.name == p.frequency, orElse: () => InvestFrequency.monthly);
                return Dismissible(
                  key: ValueKey(p.id),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) => _confirmDelete(context, ref, p.id, p.assetName),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: AppColors.error,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => context.push('/investment-plan-form?id=${p.id}'),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: (p.isActive ? AppColors.primary : AppColors.textHint).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.event_repeat, color: p.isActive ? AppColors.primary : AppColors.textHint),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.assetName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${p.assetCode} · ${freq.label} · ${FormatUtils.formatFullCurrency(p.amount)}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (p.isActive ? AppColors.success : AppColors.textHint).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                p.isActive ? '运行中' : '已暂停',
                                style: TextStyle(fontSize: 11, color: p.isActive ? AppColors.success : AppColors.textHint, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/investment-plan-form'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, WidgetRef ref, String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除定投计划'),
        content: Text('确定删除「$name」的定投计划？'),
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
      await db.deleteInvestmentPlan(id);
      ref.read(autoSyncProvider).triggerAutoSync();
      return true;
    }
    return false;
  }
}
