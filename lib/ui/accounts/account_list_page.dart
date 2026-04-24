import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/category_group.dart';
import '../../core/utils/ai_service.dart';
import '../../core/utils/ai_prompt_prefs.dart';
import '../widgets/ai_prompt_preview_dialog.dart';
import '../../providers/account_group_provider.dart';
import '../../providers/account_provider.dart';
import '../../providers/holding_provider.dart';
import '../../providers/family_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/sync_provider.dart';
import '../../data/database/app_database.dart';

final _accountMemberFilter = StateProvider<String?>((ref) => null);

class AccountListPage extends ConsumerWidget {
  const AccountListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(familyMembersProvider);
    final selectedMemberId = ref.watch(_accountMemberFilter);
    final groups = ref.watch(accountGroupByMemberProvider(selectedMemberId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('账户管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome, size: 22),
            tooltip: 'AI 智能分类',
            onPressed: () => _aiClassifyAll(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          // 成员筛选栏
          membersAsync.when(
            data: (members) {
              if (members.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('全部'),
                        selected: selectedMemberId == null,
                        onSelected: (_) => ref.read(_accountMemberFilter.notifier).state = null,
                        labelStyle: TextStyle(
                          color: selectedMemberId == null ? Colors.white : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ...members.map((m) {
                      final selected = selectedMemberId == m.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(m.name),
                          selected: selected,
                          onSelected: (_) => ref.read(_accountMemberFilter.notifier).state = selected ? null : m.id,
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
          // 机构列表
          Expanded(
            child: groups.isEmpty
                ? const Center(child: Text('暂无账户'))
                : LayoutBuilder(builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 700;
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 960),
                        child: ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16, vertical: 12),
                          itemCount: groups.length,
                          itemBuilder: (context, index) => _InstitutionTile(group: groups[index]),
                        ),
                      ),
                    );
                  }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/account-form'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _aiClassifyAll(BuildContext context, WidgetRef ref) async {
    final holdings = ref.read(allHoldingsProvider).valueOrNull ?? [];
    if (holdings.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无持仓可分类')));
      }
      return;
    }

    final holdingsData = holdings.map((h) => {
      'id': h.id, 'code': h.assetCode, 'name': h.assetName, 'type': h.assetType,
      'quantity': h.quantity, 'currentPrice': h.currentPrice,
    }).toList();

    String? promptOverride;
    if (await AiPromptPrefs.getPreviewPromptBeforeRun()) {
      final initial = AiService.buildClassifyHoldingsPrompt(holdingsData);
      if (!context.mounted) return;
      promptOverride = await showAiPromptPreviewDialog(
        context,
        title: 'AI 智能分类 — 提示词',
        initialPrompt: initial,
        confirmLabel: '确认并开始分类',
      );
      if (promptOverride == null) return;
    }

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _StreamingClassifyDialog(
        holdingsData: holdingsData,
        promptOverride: promptOverride,
      ),
    );

    if (result == null || !context.mounted) return;

    final db = ref.read(databaseProvider);
    List<dynamic> classifications;
    try {
      final trimmed = result.trim();
      if (trimmed.startsWith('[')) {
        classifications = jsonDecode(trimmed);
      } else {
        final match = RegExp(r'```(?:json)?\s*\n?([\s\S]*?)\n?```').firstMatch(trimmed);
        classifications = jsonDecode(match?.group(1)?.trim() ?? trimmed);
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI 返回格式异常，请重试')));
      return;
    }

    final assetTypeLabels = {for (final t in AssetType.values) t.name: t.label};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 智能分类结果'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: classifications.length,
            itemBuilder: (_, i) {
              final c = classifications[i] as Map<String, dynamic>;
              final holdingName = holdings.where((h) => h.id == c['id']).firstOrNull?.assetName ?? c['id'];
              final newType = c['assetType'] as String? ?? '';
              final reason = c['reason'] as String? ?? '';
              return ListTile(
                dense: true,
                title: Text(holdingName as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(reason, style: const TextStyle(fontSize: 11)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(assetTypeLabels[newType] ?? newType, style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认保存')),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      for (final c in classifications) {
        final id = c['id'] as String?;
        final newType = c['assetType'] as String?;
        if (id != null && newType != null) {
          final existing = await db.getHoldingById(id);
          if (existing != null) {
            await db.updateHolding(HoldingsCompanion(
              id: Value(id),
              accountId: Value(existing.accountId),
              assetCode: Value(existing.assetCode),
              assetName: Value(existing.assetName),
              assetType: Value(newType),
              quantity: Value(existing.quantity),
              costPrice: Value(existing.costPrice),
              currentPrice: Value(existing.currentPrice),
              tags: Value(existing.tags),
              notes: Value(existing.notes),
              createdAt: Value(existing.createdAt),
              updatedAt: Value(DateTime.now()),
            ));
          }
        }
      }
      ref.read(autoSyncProvider).triggerAutoSync();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('分类已更新')));
      }
    }
  }
}

/// 流式分类进度弹窗
class _StreamingClassifyDialog extends StatefulWidget {
  final List<Map<String, dynamic>> holdingsData;
  final String? promptOverride;
  const _StreamingClassifyDialog({required this.holdingsData, this.promptOverride});

  @override
  State<_StreamingClassifyDialog> createState() => _StreamingClassifyDialogState();
}

class _StreamingClassifyDialogState extends State<_StreamingClassifyDialog> {
  String _content = '';
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startStream();
  }

  void _startStream() {
    setState(() { _content = ''; _isLoading = true; _error = null; });

    AiService.classifyHoldingsStream(
      widget.holdingsData,
      promptOverride: widget.promptOverride,
    ).listen(
      (delta) {
        if (mounted) setState(() => _content += delta);
      },
      onError: (e) {
        if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
      },
      onDone: () {
        if (mounted) {
          setState(() => _isLoading = false);
          if (_error == null && _content.isNotEmpty) {
            Navigator.pop(context, _content);
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Text('AI 正在分析分类'),
        if (_isLoading) ...[
          const SizedBox(width: 12),
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ]),
      content: SizedBox(
        width: double.maxFinite,
        height: 200,
        child: _error != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('分析失败: $_error', style: const TextStyle(color: AppColors.error)),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _startStream, child: const Text('重试')),
                ],
              )
            : SingleChildScrollView(
                child: Text(
                  _content.isEmpty ? '正在连接 AI...' : _content,
                  style: TextStyle(fontSize: 12, color: _content.isEmpty ? AppColors.textHint : AppColors.textPrimary, fontFamily: 'monospace'),
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('取消')),
      ],
    );
  }
}

// ===== 机构分组展示 =====

class _InstitutionTile extends StatefulWidget {
  final InstitutionGroup group;
  const _InstitutionTile({required this.group});

  @override
  State<_InstitutionTile> createState() => _InstitutionTileState();
}

class _InstitutionTileState extends State<_InstitutionTile> {
  bool _expanded = true;

  Future<void> _deleteInstitution(BuildContext context) async {
    final g = widget.group;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账户'),
        content: Text('确定删除「${g.institution}」及其所有持仓和定投计划？\n\n共 ${g.holdingCount} 条持仓将被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final db = ProviderScope.containerOf(context).read(databaseProvider);
    final sync = ProviderScope.containerOf(context).read(autoSyncProvider);

    for (final accountId in g.accountIds) {
      final holdings = await db.getHoldingsByAccount(accountId);
      for (final h in holdings) { await db.deleteHolding(h.id); }
      final plans = await db.getInvestmentPlansByAccount(accountId);
      for (final p in plans) { await db.deleteInvestmentPlan(p.id); }
      await db.deleteAccount(accountId);
    }
    try { await sync.syncUp(); } catch (_) {}
    ProviderScope.containerOf(context).invalidate(allAccountsProvider);
    ProviderScope.containerOf(context).invalidate(allHoldingsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已删除「${g.institution}」')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            onLongPress: () => _deleteInstitution(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  // 第一行：机构名 + 展开箭头
                  Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
                        child: const Icon(Icons.account_balance, color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        g.institution.isEmpty ? '未知机构' : g.institution,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      )),
                      AnimatedRotation(turns: _expanded ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: const Icon(Icons.expand_more, color: AppColors.textHint)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 第二行：统计 + 金额 + 操作按钮
                  Row(
                    children: [
                      const SizedBox(width: 46), // 对齐图标
                      Text('${g.categories.length}个分类 · ${g.holdingCount}笔资产', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      const Spacer(),
                      Text(FormatUtils.formatCurrency(g.totalMarketValue), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(width: 4),
                      if (g.accountIds.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, size: 18, color: AppColors.primary),
                          tooltip: '添加持仓',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () => context.push('/holding-form?accountId=${g.accountIds.first}'),
                        ),
                      if (g.accountIds.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.camera_alt_outlined, size: 18, color: AppColors.textSecondary),
                          tooltip: '截图导入',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () => context.push('/ocr-import?accountId=${g.accountIds.first}'),
                        ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300),
                        tooltip: '删除账户',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () => _deleteInstitution(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(children: widget.group.categories.map((catSub) => _CategorySubTile(catSub: catSub)).toList()),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

class _CategorySubTile extends StatefulWidget {
  final CategorySubGroup catSub;
  const _CategorySubTile({required this.catSub});

  @override
  State<_CategorySubTile> createState() => _CategorySubTileState();
}

class _CategorySubTileState extends State<_CategorySubTile> {
  bool _expanded = false;

  Future<void> _showQuickPriceUpdate(BuildContext context, dynamic holding) async {
    final category = widget.catSub.category;
    final displayMode = getDisplayMode(category);
    final isDeposit = displayMode == HoldingDisplayMode.deposit;
    final isWealth = displayMode == HoldingDisplayMode.wealth || displayMode == HoldingDisplayMode.fixedIncome;

    // 对于存款/理财用总额，对于股票用单价
    final initialValue = isDeposit || isWealth
        ? (holding.quantity as double) * (holding.currentPrice as double)
        : (holding.currentPrice as double);
    final controller = TextEditingController(text: initialValue.toString());

    final title = isDeposit ? '更新金额' : isWealth ? '更新总市值' : '更新现价';
    final label = isDeposit ? '新金额' : isWealth ? '新总市值' : '新现价';

    final newValue = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$title · ${holding.assetName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isDeposit) ...[
              Text('成本${isWealth ? "总额" : "价"}: ${FormatUtils.formatCurrency(isWealth ? (holding.quantity as double) * (holding.costPrice as double) : (holding.costPrice as double))}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              Text('当前${isWealth ? "总市值" : "现价"}: ${FormatUtils.formatCurrency(initialValue)}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ] else ...[
              Text('当前金额: ${FormatUtils.formatCurrency(initialValue)}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(controller.text);
              Navigator.pop(ctx, v);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newValue == null || !context.mounted) return;

    // 计算实际存储值
    double newPrice;
    double newQuantity = holding.quantity as double;
    double newCost = holding.costPrice as double;
    if (isDeposit) {
      newQuantity = 1;
      newPrice = newValue;
      newCost = newValue;
    } else if (isWealth && (holding.quantity as double) <= 1) {
      // 没有份额的理财，quantity=1
      newPrice = newValue;
    } else if (isWealth) {
      // 有份额的理财，更新净值
      newPrice = newValue / (holding.quantity as double);
    } else {
      newPrice = newValue;
    }

    final db = ProviderScope.containerOf(context).read(databaseProvider);
    final sync = ProviderScope.containerOf(context).read(autoSyncProvider);
    await db.updateHolding(HoldingsCompanion(
      id: Value(holding.id as String),
      accountId: Value(holding.accountId as String),
      assetCode: Value(holding.assetCode as String),
      assetName: Value(holding.assetName as String),
      assetType: Value(holding.assetType as String),
      quantity: Value(newQuantity),
      costPrice: Value(isDeposit ? newCost : (holding.costPrice as double)),
      currentPrice: Value(newPrice),
      tags: Value(holding.tags as String),
      notes: Value(holding.notes as String),
      createdAt: Value(holding.createdAt as DateTime),
      updatedAt: Value(DateTime.now()),
    ));
    try { await sync.syncUp(); } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${holding.assetName} 现价已更新为 ${FormatUtils.formatCurrency(newPrice)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.catSub;
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: cs.category.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Icon(cs.category.icon, size: 18, color: cs.category.color),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cs.category.label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: cs.category.color)),
                    Text('${cs.holdings.length}笔', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                )),
                Text(FormatUtils.formatCurrency(cs.totalMarketValue), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(width: 4),
                AnimatedRotation(turns: _expanded ? 0.5 : 0, duration: const Duration(milliseconds: 150), child: const Icon(Icons.expand_more, size: 20, color: AppColors.textHint)),
              ],
            ),
          ),
        ),
        if (_expanded)
          ...cs.holdings.map((hs) {
            final h = hs.holding;
            return InkWell(
              onTap: () => context.push('/holding-form?id=${h.id}&accountId=${h.accountId}'),
              onLongPress: () => _showQuickPriceUpdate(context, h),
              child: Padding(
                padding: const EdgeInsets.only(left: 62, right: 16, bottom: 8, top: 2),
                child: _buildHoldingItem(h, hs.memberName, cs.category),
              ),
            );
          }),
        if (cs.holdings.isNotEmpty) const Divider(height: 1, indent: 20, endIndent: 20),
      ],
    );
  }

  /// 根据资产类型显示不同的持仓信息
  Widget _buildHoldingItem(Holding h, String memberName, CategoryGroup category) {
    final assetType = AssetType.values.where((e) => e.name == h.assetType).firstOrNull;
    final displayMode = getDisplayMode(category);

    if (displayMode == HoldingDisplayMode.deposit) {
      // 存款：只显示名称 + 金额
      final amount = h.quantity * h.currentPrice;
      return Row(
        children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(h.assetName, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 1),
              if (memberName.isNotEmpty)
                Text(memberName, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
            ],
          )),
          Text(FormatUtils.formatCurrency(amount), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 16, color: AppColors.textHint),
        ],
      );
    }

    if (displayMode == HoldingDisplayMode.wealth) {
      // 银行理财：名称 + 总市值 + 总成本 + 收益额
      final totalMv = h.quantity * h.currentPrice;
      final totalCost = h.quantity * h.costPrice;
      final pnl = totalMv - totalCost;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(h.assetName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis, maxLines: 1)),
              Text(FormatUtils.formatCurrency(totalMv), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 16, color: AppColors.textHint),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (memberName.isNotEmpty)
                Text('$memberName  ', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              const Spacer(),
              Text('成本${FormatUtils.formatCurrency(totalCost)}  ', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              Text(
                '${pnl >= 0 ? "+" : ""}${FormatUtils.formatCurrency(pnl)}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: pnl >= 0 ? AppColors.gain : AppColors.loss),
              ),
            ],
          ),
        ],
      );
    }

    if (displayMode == HoldingDisplayMode.fixedIncome) {
      // 固收基金：名称 + 份额 + 净值 + 总市值 + 收益额
      final totalMv = h.quantity * h.currentPrice;
      final totalCost = h.quantity * h.costPrice;
      final pnl = totalMv - totalCost;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(h.assetName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis, maxLines: 1)),
              Text(FormatUtils.formatCurrency(totalMv), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 16, color: AppColors.textHint),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (h.assetCode.isNotEmpty && h.assetCode != 'unknown' && h.assetCode != 'WEALTH')
                Text('${h.assetCode}  ', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              if (assetType != null)
                Text('${assetType.label}  ', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              if (memberName.isNotEmpty)
                Text(memberName, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              const Spacer(),
              if (h.quantity > 1)
                Text('${FormatUtils.formatNumber(h.quantity)}份  净值${h.currentPrice.toStringAsFixed(4)}  ', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              Text(
                '${pnl >= 0 ? "+" : ""}${FormatUtils.formatCurrency(pnl)}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: pnl >= 0 ? AppColors.gain : AppColors.loss),
              ),
            ],
          ),
        ],
      );
    }

    // 股票/权益基金：代码 + 数量 + 成本价→现价 + 盈亏%
    final mv = h.quantity * h.currentPrice;
    final pnl = (h.currentPrice - h.costPrice) * h.quantity;
    final pnlPct = h.costPrice != 0 ? (h.currentPrice - h.costPrice) / h.costPrice * 100 : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(h.assetName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis, maxLines: 1)),
            Text(FormatUtils.formatCurrency(mv), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.textHint),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            if (h.assetCode.isNotEmpty && h.assetCode != 'unknown')
              Text('${h.assetCode}  ', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
            if (assetType != null)
              Text('${assetType.label}  ', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
            if (memberName.isNotEmpty)
              Text(memberName, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
            const Spacer(),
            Text(
              '${FormatUtils.formatNumber(h.quantity)}股  ${FormatUtils.formatCurrency(h.costPrice)}→${FormatUtils.formatCurrency(h.currentPrice)}  ',
              style: const TextStyle(fontSize: 11, color: AppColors.textHint),
            ),
            Text(
              FormatUtils.formatPercent(pnlPct),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: pnl >= 0 ? AppColors.gain : AppColors.loss),
            ),
          ],
        ),
      ],
    );
  }
}
