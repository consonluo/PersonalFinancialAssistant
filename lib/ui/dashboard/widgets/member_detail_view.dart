import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/format_utils.dart';
import '../../../providers/member_detail_provider.dart';
import '../../../providers/market_provider.dart';

class MemberDetailView extends ConsumerWidget {
  final String memberId;
  const MemberDetailView({super.key, required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _HoldingsSection(memberId: memberId),
        _LiabilitiesSection(memberId: memberId),
        _InvestmentPlansSection(memberId: memberId),
        const SizedBox(height: 80),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final int count;
  const _SectionHeader(
      {required this.title, required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('$count 条',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  final VoidCallback? onAction;
  final String? actionLabel;
  const _EmptyHint({required this.text, this.onAction, this.actionLabel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              children: [
                Text(text,
                    style: const TextStyle(
                        color: AppColors.textHint, fontSize: 13)),
                if (onAction != null && actionLabel != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                      onPressed: onAction, child: Text(actionLabel!)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== Holdings ====================

class _HoldingsSection extends ConsumerWidget {
  final String memberId;
  const _HoldingsSection({required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdingsAsync = ref.watch(memberHoldingsProvider(memberId));
    final marketData = ref.watch(marketDataProvider);

    return holdingsAsync.when(
      data: (holdings) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
                title: '持仓明细',
                icon: Icons.pie_chart_outline,
                count: holdings.length),
            if (holdings.isEmpty)
              _EmptyHint(
                text: '暂无持仓',
                actionLabel: '去录入',
                onAction: () => context.push('/account-form?memberId=$memberId'),
              )
            else
              ...holdings.map((h) {
                final market = marketData[h.assetCode];
                final price = market?.price ?? h.currentPrice;
                final mv = h.quantity * price;
                final cost = h.quantity * h.costPrice;
                final pnl = mv - cost;
                final pnlPct =
                    cost > 0 ? (mv - cost) / cost * 100 : 0.0;
                final type = AssetType.values.firstWhere(
                    (e) => e.name == h.assetType,
                    orElse: () => AssetType.other);

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(type.code,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(h.assetName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                Text(
                                  '${h.assetCode} · ${h.quantity.toStringAsFixed(h.quantity == h.quantity.roundToDouble() ? 0 : 2)}份 × ¥${price.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(FormatUtils.formatCurrency(mv),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              Text(
                                '${pnl >= 0 ? "+" : ""}${FormatUtils.formatCurrency(pnl)} (${pnlPct.toStringAsFixed(1)}%)',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: pnl >= 0
                                        ? AppColors.gain
                                        : AppColors.loss),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ==================== Liabilities ====================

class _LiabilitiesSection extends ConsumerWidget {
  final String memberId;
  const _LiabilitiesSection({required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liabilitiesAsync = ref.watch(memberLiabilitiesProvider(memberId));

    return liabilitiesAsync.when(
      data: (liabilities) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
                title: '负债',
                icon: Icons.money_off_outlined,
                count: liabilities.length),
            if (liabilities.isEmpty)
              const _EmptyHint(text: '暂无负债')
            else
              ...liabilities.map((l) {
                final type = LiabilityType.values.firstWhere(
                    (e) => e.name == l.type,
                    orElse: () => LiabilityType.other);
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(type.label,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                Text(
                                  '月供 ${FormatUtils.formatCurrency(l.monthlyPayment)} · 利率 ${l.interestRate.toStringAsFixed(2)}%',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(FormatUtils.formatCurrency(l.remainingAmount),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: AppColors.error)),
                              Text(
                                '总额 ${FormatUtils.formatCurrency(l.totalAmount)}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ==================== Investment Plans ====================

class _InvestmentPlansSection extends ConsumerWidget {
  final String memberId;
  const _InvestmentPlansSection({required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(memberInvestmentPlansProvider(memberId));

    return plansAsync.when(
      data: (plans) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
                title: '定投计划',
                icon: Icons.event_repeat,
                count: plans.length),
            if (plans.isEmpty)
              const _EmptyHint(text: '暂无定投计划')
            else
              ...plans.map((p) {
                final freq = InvestFrequency.values.firstWhere(
                    (f) => f.name == p.frequency,
                    orElse: () => InvestFrequency.monthly);
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: (p.isActive
                                      ? AppColors.primary
                                      : AppColors.textHint)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.event_repeat,
                                color: p.isActive
                                    ? AppColors.primary
                                    : AppColors.textHint,
                                size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.assetName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                Text(
                                  '${p.assetCode} · ${freq.label} · ${FormatUtils.formatFullCurrency(p.amount)}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (p.isActive
                                      ? AppColors.success
                                      : AppColors.textHint)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              p.isActive ? '运行中' : '已暂停',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: p.isActive
                                      ? AppColors.success
                                      : AppColors.textHint,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
