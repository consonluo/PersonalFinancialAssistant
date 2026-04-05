import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/format_utils.dart';
import '../../providers/asset_summary_provider.dart';
import '../../providers/family_provider.dart';
import '../../providers/liability_provider.dart';
import '../../providers/market_provider.dart';
import '../../providers/current_role_provider.dart';
import '../../providers/holding_provider.dart';
import '../../providers/database_provider.dart';
import '../../data/models/asset_summary_model.dart';
import '../../core/utils/snapshot_service.dart';
import 'widgets/total_asset_card.dart';
import 'widgets/category_pie_chart.dart';

/// 当前选中的成员筛选（null = 全部）
final _selectedMemberFilter = StateProvider<String?>((ref) => null);

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(marketDataProvider.notifier).startAutoRefresh();
      // 自动记录每日资产快照
      SnapshotService(ref.read(databaseProvider)).takeSnapshotIfNeeded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(assetSummaryProvider);
    final liabilities = ref.watch(allLiabilitiesProvider).valueOrNull ?? [];
    final isDemo = ref.watch(isDemoModeProvider);
    final familyName = ref.watch(familyNameProvider);
    final membersAsync = ref.watch(familyMembersProvider);
    final selectedMemberId = ref.watch(_selectedMemberFilter);

    // 如果选中了某个成员，计算该成员的数据
    final memberFilteredData = selectedMemberId != null
        ? ref.watch(_memberSummaryProvider(selectedMemberId)).valueOrNull
        : null;

    final displayAssets = memberFilteredData?.totalAssets ?? overview.totalAssets;
    final displayCategories = memberFilteredData?.categories ?? overview.categories;
    final displayTodayChange = memberFilteredData?.todayChange ?? overview.todayChange;
    final displayTodayChangePct = memberFilteredData?.todayChangePercent ?? overview.todayChangePercent;

    // 负债：筛选成员
    final displayLiabilities = selectedMemberId != null
        ? liabilities.where((l) => l.memberId == selectedMemberId).toList()
        : liabilities;
    final displayLiabilityTotal = displayLiabilities.fold(0.0, (sum, l) => sum + l.remainingAmount);
    final netWorth = displayAssets - displayLiabilityTotal;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: Row(
              children: [
                const Icon(Icons.account_balance_wallet, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(familyName.isEmpty ? '家庭资产管理' : familyName),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_add_outlined, size: 22),
                tooltip: '添加成员',
                onPressed: () => context.push('/member-form'),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.go('/settings'),
              ),
            ],
          ),
          if (isDemo)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline, color: AppColors.warning, size: 16),
                    SizedBox(width: 8),
                    Flexible(child: Text('当前为演示模式', style: TextStyle(color: AppColors.warning, fontSize: 13))),
                  ],
                ),
              ),
            ),

          // 成员筛选横向 Chips
          SliverToBoxAdapter(
            child: membersAsync.when(
              data: (members) {
                if (members.isEmpty) return const SizedBox.shrink();
                return SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: [
                      // "全部"按钮
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('全部'),
                          selected: selectedMemberId == null,
                          onSelected: (_) => ref.read(_selectedMemberFilter.notifier).state = null,
                          labelStyle: TextStyle(
                            color: selectedMemberId == null ? Colors.white : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ...members.asMap().entries.map((e) {
                        final m = e.value;
                        final selected = selectedMemberId == m.id;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: selected
                                ? null
                                : CircleAvatar(
                                    backgroundColor: AppColors.getCategoryColor(e.key),
                                    child: Text(m.name[0], style: const TextStyle(color: Colors.white, fontSize: 11)),
                                  ),
                            label: Text(m.name),
                            selected: selected,
                            onSelected: (_) => ref.read(_selectedMemberFilter.notifier).state = selected ? null : m.id,
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),

          // 总资产卡片
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: () => context.push('/asset-trend'),
                child: TotalAssetCard(
                  totalAssets: displayAssets,
                  netWorth: netWorth,
                  todayChange: displayTodayChange,
                  todayChangePercent: displayTodayChangePct,
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // 负债 / 净资产
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _QuickStatCard(label: '总负债', value: FormatUtils.formatCurrency(displayLiabilityTotal), color: AppColors.error, onTap: () => context.push('/liabilities')),
                  const SizedBox(width: 12),
                  _QuickStatCard(label: '净资产', value: FormatUtils.formatCurrency(netWorth), color: AppColors.success, onTap: () => context.push('/balance-sheet')),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // 资产类型分布（饼图+列表）
          SliverToBoxAdapter(
            child: GestureDetector(
              onTap: () => context.go('/analysis'),
              child: CategoryPieChart(categories: displayCategories),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // 负债类型分布
          if (displayLiabilities.isNotEmpty)
            SliverToBoxAdapter(
              child: GestureDetector(
                onTap: () => context.push('/liabilities'),
                child: _LiabilityBreakdown(liabilities: displayLiabilities),
              ),
            ),

          // 快捷入口
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.home,
                      label: '其他资产',
                      color: AppColors.info,
                      onTap: () => context.push('/fixed-assets'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.money_off,
                      label: '负债管理',
                      color: AppColors.error,
                      onTap: () => context.push('/liabilities'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.show_chart,
                      label: '资产走势',
                      color: AppColors.success,
                      onTap: () => context.push('/asset-trend'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 资产明细列表
          if (displayCategories.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '资产明细',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final c = displayCategories[index];
                  final pnlColor = c.profitLoss >= 0 ? AppColors.gain : AppColors.loss;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                    child: Card(
                      child: InkWell(
                        onTap: () => context.push('/analysis/category/${c.assetType.name}'),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: AppColors.getCategoryColor(index).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(c.assetType.code, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.getCategoryColor(index))),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c.categoryName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                    Text('${c.holdingCount} 笔持仓 · ${c.proportion.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(FormatUtils.formatCurrency(c.totalMarketValue), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  Text(
                                    '${c.profitLoss >= 0 ? "+" : ""}${FormatUtils.formatCurrency(c.profitLoss)}',
                                    style: TextStyle(fontSize: 11, color: pnlColor),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
                childCount: displayCategories.length,
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAiAnalysis(context, displayCategories, displayAssets, displayLiabilityTotal),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('AI 分析'),
      ),
    );
  }

  void _showAiAnalysis(BuildContext context, List<AssetSummaryModel> categories,
      double totalAssets, double totalLiability) {
    final holdingsData = (ref.read(allHoldingsProvider).valueOrNull ?? []).map((h) {
      final mv = h.quantity * h.currentPrice;
      final pnl = h.costPrice > 0 ? ((h.currentPrice - h.costPrice) / h.costPrice * 100) : 0.0;
      return {
        'name': h.assetName, 'code': h.assetCode, 'type': h.assetType,
        'quantity': h.quantity, 'costPrice': h.costPrice, 'currentPrice': h.currentPrice,
        'marketValue': mv.toStringAsFixed(2), 'pnl': pnl.toStringAsFixed(2),
      };
    }).toList();

    final categoryData = categories.map((c) => {
      'name': c.categoryName,
      'value': c.totalMarketValue.toStringAsFixed(2),
      'percent': c.proportion.toStringAsFixed(1),
    }).toList();

    // 直接跳转到流式 AI 分析页面，无需 loading 弹窗
    context.push('/ai-analysis?title=AI 资产分析', extra: <String, dynamic>{
      'holdings': holdingsData,
      'totalAssets': totalAssets,
      'totalLiability': totalLiability,
      'categories': categoryData,
    });
  }
}

/// 按成员筛选的资产汇总 Provider
final _memberSummaryProvider = FutureProvider.family<FamilyAssetOverview, String>((ref, memberId) async {
  final db = ref.watch(databaseProvider);
  final marketData = ref.watch(marketDataProvider);
  final accounts = await db.getAccountsByMember(memberId);

  final categoryMap = <AssetType, _CatAcc>{};
  double total = 0, todayChg = 0;

  for (final acc in accounts) {
    final holdings = await db.getHoldingsByAccount(acc.id);
    for (final h in holdings) {
      final type = AssetType.values.firstWhere((e) => e.name == h.assetType, orElse: () => AssetType.other);
      final market = marketData[h.assetCode];
      final price = market?.price ?? h.currentPrice;
      final mv = h.quantity * price;
      final cost = h.quantity * h.costPrice;
      final chg = market != null ? mv * market.changePercent / 100 : 0.0;

      categoryMap.putIfAbsent(type, () => _CatAcc());
      categoryMap[type]!.mv += mv;
      categoryMap[type]!.cost += cost;
      categoryMap[type]!.chg += chg;
      categoryMap[type]!.count++;
      total += mv;
      todayChg += chg;
    }
  }

  final categories = categoryMap.entries.map((e) {
    final a = e.value;
    return AssetSummaryModel(
      assetType: e.key,
      categoryName: e.key.label,
      totalMarketValue: a.mv,
      totalCost: a.cost,
      profitLoss: a.mv - a.cost,
      profitLossPercent: a.cost != 0 ? (a.mv - a.cost) / a.cost * 100 : 0,
      proportion: total != 0 ? a.mv / total * 100 : 0,
      holdingCount: a.count,
      todayChange: a.chg,
    );
  }).toList()
    ..sort((a, b) => b.totalMarketValue.compareTo(a.totalMarketValue));

  return FamilyAssetOverview(
    totalAssets: total,
    totalInvestment: total,
    todayChange: todayChg,
    todayChangePercent: total != 0 ? todayChg / total * 100 : 0,
    categories: categories,
  );
});

class _CatAcc {
  double mv = 0, cost = 0, chg = 0;
  int count = 0;
}

/// 负债类型分布卡片
class _LiabilityBreakdown extends StatelessWidget {
  final List<dynamic> liabilities;
  const _LiabilityBreakdown({required this.liabilities});

  @override
  Widget build(BuildContext context) {
    // 按类型聚合
    final typeMap = <String, double>{};
    for (final l in liabilities) {
      final type = l.type as String;
      final label = LiabilityType.values
          .firstWhere((e) => e.name == type, orElse: () => LiabilityType.other)
          .label;
      typeMap[label] = (typeMap[label] ?? 0) + (l.remainingAmount as double);
    }

    final sorted = typeMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold(0.0, (sum, e) => sum + e.value);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('负债分布', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(FormatUtils.formatCurrency(total), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.error)),
              ],
            ),
            const SizedBox(height: 12),
            // 横向比例条
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: sorted.asMap().entries.map((e) {
                    final ratio = total > 0 ? e.value.value / total : 0.0;
                    return Expanded(
                      flex: (ratio * 100).round().clamp(1, 100),
                      child: Container(color: AppColors.getCategoryColor(e.key + 6)),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...sorted.asMap().entries.map((e) {
              final pct = total > 0 ? e.value.value / total * 100 : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(color: AppColors.getCategoryColor(e.key + 6), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e.value.key, style: const TextStyle(fontSize: 13))),
                    Text('${pct.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(width: 8),
                    Text(FormatUtils.formatCurrency(e.value.value), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _QuickStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;
  const _QuickStatCard({required this.label, required this.value, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
                  if (onTap != null)
                    Icon(Icons.chevron_right, size: 16, color: color.withValues(alpha: 0.5)),
                ],
              ),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickActionCard({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
