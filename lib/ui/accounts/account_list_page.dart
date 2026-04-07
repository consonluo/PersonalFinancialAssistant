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

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _StreamingClassifyDialog(holdingsData: holdingsData),
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
  const _StreamingClassifyDialog({required this.holdingsData});

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

    AiService.classifyHoldingsStream(widget.holdingsData).listen(
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.account_balance, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.institution.isEmpty ? '未知机构' : g.institution, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text('${g.categories.length}个分类 · ${g.holdingCount}只持仓', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  )),
                  Text(FormatUtils.formatCurrency(g.totalMarketValue), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(width: 4),
                  AnimatedRotation(turns: _expanded ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: const Icon(Icons.expand_more, color: AppColors.textHint)),
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
                    Text('${cs.holdings.length}只', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
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
            final mv = h.quantity * h.currentPrice;
            final pnl = (h.currentPrice - h.costPrice) * h.quantity;
            final pnlPct = h.costPrice != 0 ? (h.currentPrice - h.costPrice) / h.costPrice * 100 : 0.0;
            return Padding(
              padding: const EdgeInsets.only(left: 62, right: 16, bottom: 6),
              child: Row(
                children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(h.assetName, style: const TextStyle(fontSize: 13)),
                      Text('${h.assetCode}  ${hs.memberName}', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                    ],
                  )),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(FormatUtils.formatCurrency(mv), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      Text(FormatUtils.formatPercent(pnlPct), style: TextStyle(fontSize: 11, color: pnl >= 0 ? AppColors.gain : AppColors.loss)),
                    ],
                  ),
                ],
              ),
            );
          }),
        if (cs.holdings.isNotEmpty) const Divider(height: 1, indent: 20, endIndent: 20),
      ],
    );
  }
}
