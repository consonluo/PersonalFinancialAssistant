import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/category_group.dart';
import '../../providers/asset_summary_provider.dart';
import '../../providers/analysis_dimension_provider.dart';
import '../../providers/target_classification_provider.dart';
import '../../providers/holding_provider.dart';
import '../../core/utils/ai_prompt_prefs.dart';
import '../widgets/ai_prompt_preview_dialog.dart';

class AnalysisPage extends ConsumerWidget {
  const AnalysisPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('资产分析'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '按分类'),
              Tab(text: '按市场'),
              Tab(text: '按品种'),
              Tab(text: '按标签'),
              Tab(text: 'AI聚类'),
            ],
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: const TabBarView(
              children: [
                _CategoryTab(),
                _MarketTab(),
                _AssetTab(),
                _TagTab(),
                _TargetTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ======== 按分类 Tab ========

class _CategoryTab extends ConsumerWidget {
  const _CategoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(assetSummaryProvider);
    final categories = overview.categories;
    if (categories.isEmpty) return const Center(child: Text('暂无数据'));

    final grouped = groupCategories(categories);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _StatChip(label: '投资总额', value: FormatUtils.formatCurrency(overview.totalInvestment), color: AppColors.primary),
              _StatChip(label: '今日收益', value: FormatUtils.formatChange(overview.todayChange), color: overview.todayChange >= 0 ? AppColors.gain : AppColors.loss),
              _StatChip(label: '分类数', value: '${grouped.length}', color: AppColors.info),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: InkWell(
            onTap: () => context.push('/asset-trend'),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.show_chart, color: AppColors.success),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('资产走势图', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        Text('查看资产历史变化趋势', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textHint),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...grouped.map((g) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => context.push('/analysis/category-group/${g.group.name}'),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: g.group.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(g.group.icon, size: 20, color: g.group.color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(g.group.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: g.proportion / 100,
                            backgroundColor: AppColors.backgroundCard,
                            color: g.group.color,
                          ),
                          const SizedBox(height: 4),
                          Text('${g.holdingCount}只  占比 ${g.proportion.toStringAsFixed(1)}%',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(FormatUtils.formatCurrency(g.totalMarketValue),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          FormatUtils.formatChange(g.profitLoss),
                          style: TextStyle(fontSize: 12, color: g.profitLoss >= 0 ? AppColors.gain : AppColors.loss),
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
  }
}

// ======== 按市场 Tab ========

class _MarketTab extends ConsumerWidget {
  const _MarketTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marketGroups = ref.watch(marketGroupProvider);
    if (marketGroups.isEmpty) return const Center(child: Text('暂无数据'));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: marketGroups.length,
      itemBuilder: (context, index) {
        return _MarketGroupTile(group: marketGroups[index]);
      },
    );
  }
}

class _MarketGroupTile extends StatefulWidget {
  final MarketGroupData group;
  const _MarketGroupTile({required this.group});

  @override
  State<_MarketGroupTile> createState() => _MarketGroupTileState();
}

class _MarketGroupTileState extends State<_MarketGroupTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.market.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text('${g.holdingCount}只  占比 ${g.proportion.toStringAsFixed(1)}%',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Text(FormatUtils.formatCurrency(g.totalMarketValue),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more, color: AppColors.textHint),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: g.holdings.map((h) => ListTile(
                dense: true,
                title: Text(h.assetName, style: const TextStyle(fontSize: 13)),
                subtitle: Text(h.assetCode, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(FormatUtils.formatCurrency(h.marketValue), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(
                      FormatUtils.formatPercent(h.pnlPercent),
                      style: TextStyle(fontSize: 11, color: h.pnl >= 0 ? AppColors.gain : AppColors.loss),
                    ),
                  ],
                ),
              )).toList(),
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

// ======== 按品种 Tab ========

class _AssetTab extends ConsumerWidget {
  const _AssetTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(assetTypeGroupProvider);
    if (groups.isEmpty) return const Center(child: Text('暂无数据'));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      itemBuilder: (context, index) => _AssetTypeGroupTile(group: groups[index]),
    );
  }
}

class _AssetTypeGroupTile extends StatefulWidget {
  final AssetTypeGroupData group;
  const _AssetTypeGroupTile({required this.group});

  @override
  State<_AssetTypeGroupTile> createState() => _AssetTypeGroupTileState();
}

class _AssetTypeGroupTileState extends State<_AssetTypeGroupTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final pnlColor = g.totalPnl >= 0 ? AppColors.gain : AppColors.loss;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.assetType.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text('${g.holdingCount}只  占比 ${g.proportion.toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  )),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(FormatUtils.formatCurrency(g.totalMarketValue),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(FormatUtils.formatChange(g.totalPnl),
                          style: TextStyle(fontSize: 12, color: pnlColor)),
                    ],
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more, color: AppColors.textHint),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(children: g.items.map((a) {
              final itemPnlColor = a.totalPnl >= 0 ? AppColors.gain : AppColors.loss;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.assetName, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                        Text('${a.assetCode}  数量 ${FormatUtils.formatQuantity(a.totalQuantity)}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                      ],
                    )),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(FormatUtils.formatCurrency(a.totalMarketValue),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(FormatUtils.formatPercent(a.pnlPercent),
                            style: TextStyle(fontSize: 11, color: itemPnlColor)),
                      ],
                    ),
                  ],
                ),
              );
            }).toList()),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
          if (_expanded) const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _InfoCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _InfoCell({required this.label, required this.value, this.color});

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

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.7)]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ======== 按标的 Tab（AI 驱动） ========

class _TargetTab extends ConsumerWidget {
  const _TargetTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(targetClassificationProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7E57C2).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.psychology, size: 20, color: Color(0xFF7E57C2)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI 标的分类', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        Text('按投资标的/策略对持仓进行智能聚合', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    )),
                    if (state.isLoading)
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      FilledButton.tonal(
                        onPressed: () async {
                          final notifier = ref.read(targetClassificationProvider.notifier);
                          final holdings = ref.read(allHoldingsProvider).valueOrNull ?? [];
                          if (holdings.isEmpty) return;
                          final list = holdings.map((h) => {
                            'id': h.id,
                            'code': h.assetCode,
                            'name': h.assetName,
                            'type': h.assetType,
                          }).toList();
                          String? override;
                          if (await AiPromptPrefs.getPreviewPromptBeforeRun()) {
                            if (!context.mounted) return;
                            override = await showAiPromptPreviewDialog(
                              context,
                              title: 'AI 标的分类 — 提示词',
                              initialPrompt: TargetClassificationNotifier.buildTargetClassificationPrompt(list),
                              confirmLabel: '确认并开始分类',
                            );
                            if (override == null) return;
                          }
                          if (!context.mounted) return;
                          await notifier.classifyStream(promptOverride: override);
                        },
                        child: Text(state.groups.isEmpty ? '开始分类' : '重新分类'),
                      ),
                  ],
                ),
                if (state.lastUpdated != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '上次更新：${_formatTime(state.lastUpdated!)}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (state.error != null) ...[
          const SizedBox(height: 8),
          Card(
            color: AppColors.error.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(state.error!, style: const TextStyle(fontSize: 13, color: AppColors.error))),
                ],
              ),
            ),
          ),
        ],
        if (state.isLoading) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      const Text(
                        '正在请求 AI 分析…',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  if (state.streamText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundCard,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          state.streamText,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (state.groups.isEmpty && !state.isLoading && state.error == null) ...[
          const SizedBox(height: 40),
          const Center(child: Column(
            children: [
              Icon(Icons.psychology_outlined, size: 48, color: AppColors.textHint),
              SizedBox(height: 12),
              Text('点击「开始分类」让 AI 分析持仓标的', style: TextStyle(color: AppColors.textSecondary)),
              SizedBox(height: 4),
              Text('需要先在设置中配置 AI API Key', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
            ],
          )),
        ],
        const SizedBox(height: 8),
        ...state.groups.map((g) => _TargetGroupTile(group: g)),
      ],
    );
  }

  static String _formatTime(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _TargetGroupTile extends StatefulWidget {
  final TargetGroup group;
  const _TargetGroupTile({required this.group});

  @override
  State<_TargetGroupTile> createState() => _TargetGroupTileState();
}

class _TargetGroupTileState extends State<_TargetGroupTile> {
  bool _expanded = false;

  static const _colors = [
    Color(0xFFE53935), Color(0xFF5C6BC0), Color(0xFF26A69A),
    Color(0xFFFF7043), Color(0xFF7E57C2), Color(0xFF29B6F6),
    Color(0xFFAB47BC), Color(0xFF66BB6A), Color(0xFFEF5350),
    Color(0xFF42A5F5),
  ];

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final color = _colors[g.name.hashCode.abs() % _colors.length];
    final pnlColor = g.totalPnl >= 0 ? AppColors.gain : AppColors.loss;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(child: Text(
                      g.name.characters.first,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
                    )),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text('${g.holdings.length}只  占比 ${g.proportion.toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  )),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(FormatUtils.formatCurrency(g.totalMarketValue),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      Text(FormatUtils.formatChange(g.totalPnl),
                          style: TextStyle(fontSize: 11, color: pnlColor)),
                    ],
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more, color: AppColors.textHint, size: 20),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (g.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Text(g.description,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
                  ),
                ...g.holdings.map((h) {
                  final hPnlColor = h.pnl >= 0 ? AppColors.gain : AppColors.loss;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    child: Row(
                      children: [
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(h.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            Text('${h.code}  ${h.reason}',
                                style: const TextStyle(fontSize: 10, color: AppColors.textHint),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        )),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(FormatUtils.formatCurrency(h.marketValue),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            Text(FormatUtils.formatPercent(h.pnlPercent),
                                style: TextStyle(fontSize: 11, color: hPnlColor)),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

// ======== 按标签 Tab ========

class _TagTab extends ConsumerWidget {
  const _TagTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdings = ref.watch(allHoldingsProvider).valueOrNull ?? [];

    // 收集所有标签并分组
    final tagGroups = <String, List<_TagHoldingItem>>{};
    double grandTotal = 0;

    for (final h in holdings) {
      if (h.quantity == 0) continue;
      final tags = _parseHoldingTags(h.tags);
      if (tags.isEmpty) {
        // 没有标签的归入"未分类"
        tagGroups.putIfAbsent('未分类', () => []).add(_TagHoldingItem(
          id: h.id, name: h.assetName, code: h.assetCode,
          marketValue: h.quantity * h.currentPrice,
        ));
        grandTotal += h.quantity * h.currentPrice;
      } else {
        for (final tag in tags) {
          final mv = h.quantity * h.currentPrice;
          tagGroups.putIfAbsent(tag, () => []).add(_TagHoldingItem(
            id: h.id, name: h.assetName, code: h.assetCode,
            marketValue: mv,
          ));
          grandTotal += mv / tags.length; // 避免重复计算
        }
      }
    }

    if (tagGroups.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.label_off_outlined, size: 48, color: AppColors.textHint),
            SizedBox(height: 12),
            Text('暂无数据', style: TextStyle(color: AppColors.textSecondary)),
            SizedBox(height: 4),
            Text('添加持仓时设置投资标的标签', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
          ],
        ),
      );
    }

    // 按总市值排序
    final sortedTags = tagGroups.entries.toList()
      ..sort((a, b) {
        final aTotal = a.value.fold<double>(0, (sum, item) => sum + item.marketValue);
        final bTotal = b.value.fold<double>(0, (sum, item) => sum + item.marketValue);
        return bTotal.compareTo(aTotal);
      });

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedTags.length,
      itemBuilder: (context, index) {
        final tag = sortedTags[index].key;
        final items = sortedTags[index].value;
        final tagTotal = items.fold<double>(0, (sum, item) => sum + item.marketValue);
        final proportion = grandTotal > 0 ? tagTotal / grandTotal * 100 : 0.0;

        return _TagGroupTile(
          tag: tag,
          items: items,
          totalValue: tagTotal,
          proportion: proportion,
        );
      },
    );
  }

  List<String> _parseHoldingTags(String? tagsStr) {
    if (tagsStr == null || tagsStr.isEmpty) return [];
    if (tagsStr.startsWith('[')) {
      try {
        final list = jsonDecode(tagsStr);
        if (list is List) return list.map((e) => e.toString()).toList();
      } catch (_) {}
    }
    return tagsStr.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  }
}

class _TagHoldingItem {
  final String id;
  final String name;
  final String code;
  final double marketValue;
  _TagHoldingItem({
    required this.id, required this.name, required this.code, required this.marketValue,
  });
}

class _TagGroupTile extends StatefulWidget {
  final String tag;
  final List<_TagHoldingItem> items;
  final double totalValue;
  final double proportion;

  const _TagGroupTile({
    required this.tag, required this.items, required this.totalValue, required this.proportion,
  });

  @override
  State<_TagGroupTile> createState() => _TagGroupTileState();
}

class _TagGroupTileState extends State<_TagGroupTile> {
  bool _expanded = false;

  static const _tagColors = [
    Color(0xFF5C6BC0), Color(0xFF26A69A), Color(0xFFFF7043),
    Color(0xFF7E57C2), Color(0xFF29B6F6), Color(0xFFAB47BC),
    Color(0xFF66BB6A), Color(0xFFEF5350), Color(0xFF42A5F5),
    Color(0xFFE53935),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _tagColors[widget.tag.hashCode.abs() % _tagColors.length];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(child: Text(
                      widget.tag.characters.first,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
                    )),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(widget.tag, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                        ),
                        const SizedBox(width: 8),
                        Text('${widget.items.length}只', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(width: 4),
                        Text('${widget.proportion.toStringAsFixed(1)}%',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ]),
                    ],
                  )),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(FormatUtils.formatCurrency(widget.totalValue),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more, color: AppColors.textHint, size: 20),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: widget.items.map((item) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          Text(item.code, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
                        ],
                      )),
                      Text(FormatUtils.formatCurrency(item.marketValue),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              }).toList(),
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}
