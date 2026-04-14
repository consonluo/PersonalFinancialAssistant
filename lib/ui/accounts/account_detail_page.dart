import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format_utils.dart';
import '../../providers/account_provider.dart';
import '../../providers/holding_provider.dart';
import '../../providers/market_provider.dart';
import '../../providers/investment_plan_provider.dart';
import '../../providers/liability_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/sync_provider.dart';

class AccountDetailPage extends ConsumerWidget {
  final String accountId;
  const AccountDetailPage({super.key, required this.accountId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(accountByIdProvider(accountId));
    final holdingsAsync = ref.watch(holdingsByAccountProvider(accountId));
    final plansAsync = ref.watch(investmentPlansByAccountProvider(accountId));
    final liabilitiesAsync = ref.watch(allLiabilitiesProvider);
    final marketData = ref.watch(marketDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: accountAsync.whenOrNull(data: (a) => Text(a?.name ?? '')) ?? const Text('账户详情'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: holdingsAsync.when(
        data: (holdings) {
          double totalMv = 0, totalCost = 0, todayChg = 0;
          for (final h in holdings) {
            final market = marketData[h.assetCode];
            final price = market?.price ?? h.currentPrice;
            final mv = h.quantity * price;
            totalMv += mv;
            totalCost += h.quantity * h.costPrice;
            todayChg += market != null ? mv * market.changePercent / 100 : 0.0;
          }
          final totalPnl = totalMv - totalCost;

          final account = accountAsync.valueOrNull;
          final memberId = account?.memberId;
          final memberLiabilities = (liabilitiesAsync.valueOrNull ?? [])
              .where((l) => memberId != null && l.memberId == memberId)
              .toList();
          final plans = plansAsync.valueOrNull ?? [];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _AccountSummaryCard(
                totalMv: totalMv,
                totalPnl: totalPnl,
                todayChg: todayChg,
                holdingCount: holdings.length,
              ),
              const SizedBox(height: 16),

              if (holdings.isNotEmpty) ...[
                _SectionHeader(title: '持仓明细', count: holdings.length),
                const SizedBox(height: 8),
                ...holdings.map((h) {
                  final market = marketData[h.assetCode];
                  final price = market?.price ?? h.currentPrice;
                  final mv = h.quantity * price;
                  final pnl = (price - h.costPrice) * h.quantity;
                  final pnlPct = h.costPrice != 0 ? (price - h.costPrice) / h.costPrice * 100 : 0.0;
                  final todayChgPct = market?.changePercent ?? 0.0;

                  return Dismissible(
                    key: ValueKey(h.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('删除持仓'),
                          content: Text('确定删除「${h.assetName}」？'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: AppColors.error))),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        ref.read(databaseProvider).deleteHolding(h.id);
                        ref.read(autoSyncProvider).triggerAutoSync();
                        return true;
                      }
                      return false;
                    },
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: AppColors.error,
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    child: Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => context.push('/holding-form?id=${h.id}&accountId=$accountId'),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(h.assetName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                    Text(h.assetCode, style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(FormatUtils.formatFullCurrency(mv), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                  Text(
                                    '${pnl >= 0 ? "+" : ""}${FormatUtils.formatFullCurrency(pnl)} (${FormatUtils.formatPercent(pnlPct)})',
                                    style: TextStyle(fontSize: 11, color: pnl >= 0 ? AppColors.gain : AppColors.loss),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(height: 14),
                          Row(
                            children: [
                              _DetailChip(label: '数量', value: FormatUtils.formatQuantity(h.quantity)),
                              _DetailChip(label: '现价', value: FormatUtils.formatPrice(price)),
                              _DetailChip(label: '成本', value: FormatUtils.formatPrice(h.costPrice)),
                              _DetailChip(
                                label: '今日',
                                value: '${todayChgPct >= 0 ? "+" : ""}${todayChgPct.toStringAsFixed(2)}%',
                                color: todayChgPct >= 0 ? AppColors.gain : AppColors.loss,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
              ],

              if (plans.isNotEmpty) ...[
                _SectionHeader(title: '定投计划', count: plans.length),
                const SizedBox(height: 8),
                ...plans.map((p) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: p.isActive ? AppColors.success.withValues(alpha: 0.1) : AppColors.textHint.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.event_repeat, size: 20,
                          color: p.isActive ? AppColors.success : AppColors.textHint),
                    ),
                    title: Text(p.assetName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: Text('${p.frequency} · ${p.assetCode}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(FormatUtils.formatFullCurrency(p.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(p.isActive ? '执行中' : '已暂停',
                            style: TextStyle(fontSize: 11, color: p.isActive ? AppColors.success : AppColors.textHint)),
                      ],
                    ),
                  ),
                )),
                const SizedBox(height: 16),
              ],

              if (memberLiabilities.isNotEmpty) ...[
                _SectionHeader(title: '关联负债', count: memberLiabilities.length),
                const SizedBox(height: 8),
                ...memberLiabilities.map((l) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.money_off, size: 20, color: AppColors.error),
                    ),
                    title: Text(l.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: Text('${l.type} · 利率 ${l.interestRate.toStringAsFixed(2)}%',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(FormatUtils.formatFullCurrency(l.remainingAmount),
                            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.error)),
                        Text('月供 ${FormatUtils.formatFullCurrency(l.monthlyPayment)}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                )),
                const SizedBox(height: 16),
              ],

              if (holdings.isEmpty && plans.isEmpty && memberLiabilities.isEmpty)
                const Center(child: Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Text('暂无数据', style: TextStyle(color: AppColors.textSecondary)),
                )),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
      ),
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

class _AccountSummaryCard extends StatelessWidget {
  final double totalMv;
  final double totalPnl;
  final double todayChg;
  final int holdingCount;
  const _AccountSummaryCard({required this.totalMv, required this.totalPnl, required this.todayChg, required this.holdingCount});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('总市值', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 4),
            Text(FormatUtils.formatFullCurrency(totalMv),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                _MiniStat(
                  label: '盈亏',
                  value: FormatUtils.formatChange(totalPnl),
                  color: totalPnl >= 0 ? AppColors.gain : AppColors.loss,
                ),
                const SizedBox(width: 20),
                _MiniStat(
                  label: '今日涨跌',
                  value: FormatUtils.formatChange(todayChg),
                  color: todayChg >= 0 ? AppColors.gain : AppColors.loss,
                ),
                const SizedBox(width: 20),
                _MiniStat(label: '持仓数', value: '$holdingCount', color: AppColors.textPrimary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 16, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Text('$count', style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _DetailChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _DetailChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}
