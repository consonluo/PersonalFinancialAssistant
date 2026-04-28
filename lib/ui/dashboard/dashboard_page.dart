import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/category_group.dart';
import '../../core/utils/snapshot_service.dart';
import '../../providers/asset_summary_provider.dart';
import '../../providers/family_provider.dart';
import '../../providers/liability_provider.dart';
import '../../providers/market_provider.dart';
import '../../providers/current_role_provider.dart';
import '../../providers/holding_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/investment_plan_provider.dart';
import '../../data/models/asset_summary_model.dart';
import '../../core/utils/ai_prompt_prefs.dart';
import '../../core/utils/ai_service.dart';
import '../../ui/widgets/ai_prompt_preview_dialog.dart';
import 'widgets/total_asset_card.dart';
import 'widgets/mini_trend_chart.dart';
import 'widgets/member_asset_bar.dart';
import 'widgets/member_detail_view.dart';
import 'widgets/grouped_pie_chart.dart';

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
    Future.microtask(() async {
      ref.read(marketDataProvider.notifier).startAutoRefresh();
      try {
        SnapshotService(ref.read(databaseProvider)).takeSnapshotIfNeeded();
      } catch (_) {}

      // 启动时先从云端拉取最新数据，再上传本地变更
      // 解决多设备/浏览器间数据同步问题
      // skipIfRecent: 若刚在登录流程中完成了 syncDown 则跳过，避免重复清库导入
      final familyId = ref.read(familyIdProvider);
      if (familyId != null && familyId.isNotEmpty) {
        Future.delayed(const Duration(seconds: 2), () async {
          try {
            await ref.read(autoSyncProvider).syncDown(familyId, skipIfRecent: true);
          } catch (e) {
            debugPrint('[Dashboard] syncDown error: $e');
          }
        });
      }

      Future.delayed(const Duration(seconds: 10), () {
        try { ref.read(autoSyncProvider).triggerAutoSync(); } catch (_) {}
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(assetSummaryProvider);
    final liabilities = ref.watch(allLiabilitiesProvider).valueOrNull ?? [];
    final isDemo = ref.watch(isDemoModeProvider);
    final familyName = ref.watch(familyNameProvider);
    final membersAsync = ref.watch(familyMembersProvider);
    var selectedMemberId = ref.watch(_selectedMemberFilter);

    final members = membersAsync.valueOrNull ?? [];
    if (selectedMemberId != null && members.isNotEmpty && !members.any((m) => m.id == selectedMemberId)) {
      Future.microtask(() => ref.read(_selectedMemberFilter.notifier).state = null);
      selectedMemberId = null;
    }

    final memberFilteredData = selectedMemberId != null
        ? ref.watch(_memberSummaryProvider(selectedMemberId)).valueOrNull
        : null;

    final displayAssets = memberFilteredData?.totalAssets ?? overview.totalAssets;
    final displayCategories = memberFilteredData?.categories ?? overview.categories;
    final displayTodayChange = memberFilteredData?.todayChange ?? overview.todayChange;
    final displayTodayChangePct = memberFilteredData?.todayChangePercent ?? overview.todayChangePercent;

    final displayLiabilities = selectedMemberId != null
        ? liabilities.where((l) => l.memberId == selectedMemberId).toList()
        : liabilities;
    final displayLiabilityTotal = displayLiabilities.fold(0.0, (sum, l) => sum + l.remainingAmount);
    final netWorth = displayAssets - displayLiabilityTotal;

    return Scaffold(
      body: LayoutBuilder(builder: (context, constraints) {
        final screenW = constraints.maxWidth;
        final isWide = screenW >= 840;
        final pad = isWide ? 24.0 : 16.0;

        return CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              title: Row(
                children: [
                  const Icon(Icons.account_balance_wallet, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(familyName.isEmpty ? '加财' : familyName),
                ],
              ),
              actions: [
                IconButton(icon: const Icon(Icons.person_add_outlined, size: 22), tooltip: '添加成员', onPressed: () => context.push('/member-form')),
                IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => context.go('/settings')),
              ],
            ),
            if (isDemo)
              SliverToBoxAdapter(
                child: _CenterPad(pad: pad, child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline, color: AppColors.warning, size: 16),
                      SizedBox(width: 8),
                      Flexible(child: Text('当前为演示模式', style: TextStyle(color: AppColors.warning, fontSize: 13))),
                    ],
                  ),
                )),
              ),

            // Pinned 成员筛选
            membersAsync.when(
              data: (members) {
                if (members.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
                return SliverPersistentHeader(
                  pinned: true,
                  delegate: _MemberTabDelegate(members: members, selectedMemberId: selectedMemberId, onSelect: (id) => ref.read(_selectedMemberFilter.notifier).state = id),
                );
              },
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),

            if (selectedMemberId == null) ...[
              // ===== 全部 Tab =====

              if (isWide) ...[
                // 宽屏：总资产卡片 + 迷你走势并排
                SliverToBoxAdapter(child: _CenterPad(pad: pad, child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: TotalAssetCard(
                      totalAssets: displayAssets, netWorth: netWorth,
                      todayChange: displayTodayChange, todayChangePercent: displayTodayChangePct,
                      onTapTotal: () => context.push('/total-assets'),
                      onTapToday: () => context.push('/today-change'),
                    )),
                    const SizedBox(width: 16),
                    const Expanded(flex: 2, child: MiniTrendChart()),
                  ],
                ))),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // 宽屏：负债/净资产 + 快捷入口并排
                SliverToBoxAdapter(child: _CenterPad(pad: pad, child: Row(
                  children: [
                    _QuickStatCard(label: '总负债', value: FormatUtils.formatCurrency(displayLiabilityTotal), color: AppColors.error, onTap: () => context.push('/liabilities')),
                    const SizedBox(width: 12),
                    _QuickStatCard(label: '净资产', value: FormatUtils.formatCurrency(netWorth), color: AppColors.success, onTap: () => context.push('/balance-sheet')),
                    const SizedBox(width: 24),
                    Expanded(child: _QuickActionCard(icon: Icons.home, label: '其他资产', color: AppColors.info, onTap: () => context.push('/fixed-assets'))),
                    const SizedBox(width: 8),
                    Expanded(child: _QuickActionCard(icon: Icons.money_off, label: '负债管理', color: AppColors.error, onTap: () => context.push('/liabilities'))),
                    const SizedBox(width: 8),
                    Expanded(child: _QuickActionCard(icon: Icons.event_repeat, label: '定投计划', color: AppColors.primary, onTap: () => context.push('/investment-plans'))),
                    const SizedBox(width: 8),
                    Expanded(child: _QuickActionCard(icon: Icons.show_chart, label: '资产走势', color: AppColors.success, onTap: () => context.push('/asset-trend'))),
                  ],
                ))),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // 宽屏：饼图 + 分类网格并排
                if (displayCategories.isNotEmpty)
                  SliverToBoxAdapter(child: _CenterPad(pad: pad, child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: GroupedPieChart(grouped: groupCategories(displayCategories))),
                      const SizedBox(width: 16),
                      Expanded(child: _GroupedCategoryGrid(categories: displayCategories)),
                    ],
                  ))),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                SliverToBoxAdapter(child: _CenterPad(pad: pad, child: const MemberAssetBar())),
              ] else ...[
                // 窄屏：原有纵向布局
                SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: TotalAssetCard(
                  totalAssets: displayAssets, netWorth: netWorth,
                  todayChange: displayTodayChange, todayChangePercent: displayTodayChangePct,
                  onTapTotal: () => context.push('/total-assets'),
                  onTapToday: () => context.push('/today-change'),
                ))),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                const SliverToBoxAdapter(child: MiniTrendChart()),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: Row(children: [
                  _QuickStatCard(label: '总负债', value: FormatUtils.formatCurrency(displayLiabilityTotal), color: AppColors.error, onTap: () => context.push('/liabilities')),
                  const SizedBox(width: 12),
                  _QuickStatCard(label: '净资产', value: FormatUtils.formatCurrency(netWorth), color: AppColors.success, onTap: () => context.push('/balance-sheet')),
                ]))),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                if (displayCategories.isNotEmpty)
                  SliverToBoxAdapter(child: GroupedPieChart(grouped: groupCategories(displayCategories))),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                if (displayCategories.isNotEmpty)
                  SliverToBoxAdapter(child: _GroupedCategoryGrid(categories: displayCategories)),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                const SliverToBoxAdapter(child: MemberAssetBar()),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: Row(children: [
                  Expanded(child: _QuickActionCard(icon: Icons.home, label: '其他资产', color: AppColors.info, onTap: () => context.push('/fixed-assets'))),
                  const SizedBox(width: 12),
                  Expanded(child: _QuickActionCard(icon: Icons.money_off, label: '负债管理', color: AppColors.error, onTap: () => context.push('/liabilities'))),
                  const SizedBox(width: 12),
                  Expanded(child: _QuickActionCard(icon: Icons.event_repeat, label: '定投计划', color: AppColors.primary, onTap: () => context.push('/investment-plans'))),
                  const SizedBox(width: 12),
                  Expanded(child: _QuickActionCard(icon: Icons.show_chart, label: '资产走势', color: AppColors.success, onTap: () => context.push('/asset-trend'))),
                ]))),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ] else ...[
              // ===== 成员 Tab =====
              SliverToBoxAdapter(child: _CenterPad(pad: pad, child: Row(children: [
                _QuickStatCard(label: '总资产', value: FormatUtils.formatCurrency(displayAssets), color: AppColors.primary),
                const SizedBox(width: 8),
                _QuickStatCard(label: '负债', value: FormatUtils.formatCurrency(displayLiabilityTotal), color: AppColors.error),
                const SizedBox(width: 8),
                _QuickStatCard(label: '净值', value: FormatUtils.formatCurrency(netWorth), color: AppColors.success),
              ]))),
              SliverToBoxAdapter(child: _CenterPad(pad: pad, child: MemberDetailView(memberId: selectedMemberId!))),
            ],
          ],
        );
      }),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAiAnalysis(context, displayCategories, displayAssets, displayLiabilityTotal),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('AI 分析'),
      ),
    );
  }

  Future<void> _showAiAnalysis(BuildContext context, List<AssetSummaryModel> categories,
      double totalAssets, double totalLiability) async {
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

    final plans = ref.read(allInvestmentPlansProvider).valueOrNull ?? [];
    final plansData = plans.map((p) => {
      'name': p.assetName, 'code': p.assetCode,
      'amount': p.amount.toStringAsFixed(2),
      'frequency': p.frequency, 'isActive': p.isActive,
    }).toList();

    String? promptOverride;
    if (await AiPromptPrefs.getPreviewPromptBeforeRun()) {
      final initial = AiService.buildAnalyzePortfolioPrompt(
        holdings: holdingsData,
        totalAssets: totalAssets,
        totalLiability: totalLiability,
        categories: categoryData,
        investmentPlans: plansData,
      );
      if (!context.mounted) return;
      promptOverride = await showAiPromptPreviewDialog(
        context,
        title: 'AI 资产分析 — 提示词',
        initialPrompt: initial,
        confirmLabel: '确认并开始分析',
      );
      if (promptOverride == null) return;
    }

    if (!context.mounted) return;
    context.push('/ai-analysis?title=AI 资产分析', extra: <String, dynamic>{
      'holdings': holdingsData,
      'totalAssets': totalAssets,
      'totalLiability': totalLiability,
      'categories': categoryData,
      'investmentPlans': plansData,
      if (promptOverride != null) 'promptOverride': promptOverride,
    });
  }
}

// ===== 响应式 Padding 包装 =====
class _CenterPad extends StatelessWidget {
  final double pad;
  final Widget child;
  const _CenterPad({required this.pad, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: child);
  }
}

// ===== Pinned Member Tab Delegate =====

class _MemberTabDelegate extends SliverPersistentHeaderDelegate {
  final List<dynamic> members;
  final String? selectedMemberId;
  final ValueChanged<String?> onSelect;

  _MemberTabDelegate({required this.members, required this.selectedMemberId, required this.onSelect});

  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.backgroundLight,
      child: SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: const Text('全部'),
                selected: selectedMemberId == null,
                onSelected: (_) => onSelect(null),
                labelStyle: TextStyle(color: selectedMemberId == null ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w600),
              ),
            ),
            ...members.asMap().entries.map((e) {
              final m = e.value;
              final selected = selectedMemberId == m.id;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: selected ? null : CircleAvatar(backgroundColor: AppColors.getCategoryColor(e.key), child: Text(m.name[0], style: const TextStyle(color: Colors.white, fontSize: 11))),
                  label: Text(m.name),
                  selected: selected,
                  onSelected: (_) => onSelect(selected ? null : m.id),
                  labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w600),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _MemberTabDelegate oldDelegate) {
    return selectedMemberId != oldDelegate.selectedMemberId || members.length != oldDelegate.members.length;
  }
}

// ===== 大类网格 =====

class _GroupedCategoryGrid extends StatelessWidget {
  final List<AssetSummaryModel> categories;
  const _GroupedCategoryGrid({required this.categories});

  @override
  Widget build(BuildContext context) {
    final grouped = groupCategories(categories);
    if (grouped.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('资产分类', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final cols = constraints.maxWidth > 400 ? 3 : 2;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: cols == 3 ? 1.9 : 2.2,
                children: grouped.map((g) {
                  return GestureDetector(
                    onTap: () => context.push('/analysis/category-group/${g.group.name}'),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: g.group.color.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: g.group.color.withValues(alpha: 0.15)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(children: [
                            Icon(g.group.icon, size: 15, color: g.group.color),
                            const SizedBox(width: 4),
                            Expanded(child: Text(g.group.label, style: TextStyle(fontSize: 12, color: g.group.color, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                            Text('${g.proportion.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                          ]),
                          const SizedBox(height: 4),
                          Text(FormatUtils.formatCurrency(g.totalMarketValue), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ===== 按成员筛选的资产汇总 Provider =====

final _memberSummaryProvider = FutureProvider.family<FamilyAssetOverview, String>((ref, memberId) async {
  final db = ref.watch(databaseProvider);
  final marketData = ref.watch(marketDataProvider);
  final accounts = await db.getAccountsByMember(memberId);

  final categoryMap = <AssetType, _CatAcc>{};
  double total = 0, todayChg = 0;

  for (final acc in accounts) {
    final holdings = await db.getHoldingsByAccount(acc.id);
    for (final h in holdings) {
      if (h.quantity == 0) continue;
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

// ===== 通用组件 =====

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
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
                if (onTap != null) Icon(Icons.chevron_right, size: 16, color: color.withValues(alpha: 0.5)),
              ]),
              const SizedBox(height: 4),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700))),
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
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}
