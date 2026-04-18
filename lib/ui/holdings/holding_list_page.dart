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
import '../../providers/holding_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/investment_plan_provider.dart';
import '../../data/database/app_database.dart';

class HoldingListPage extends ConsumerWidget {
  final String accountId;
  const HoldingListPage({super.key, required this.accountId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdingsAsync = ref.watch(holdingsByAccountProvider(accountId));
    final plansAsync = ref.watch(investmentPlansByAccountProvider(accountId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('持仓列表'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome, size: 22),
            tooltip: 'AI 智能分类',
            onPressed: () => _aiClassify(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: '截图导入',
            onPressed: () => context.push('/ocr-import?accountId=$accountId'),
          ),
        ],
      ),
      body: holdingsAsync.when(
        data: (holdings) {
          if (holdings.isEmpty) return const Center(child: Text('暂无持仓'));
          final plans = plansAsync.valueOrNull ?? [];
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: holdings.length,
            itemBuilder: (context, index) {
              final h = holdings[index];
              final assetType = AssetType.values.where((e) => e.name == h.assetType).firstOrNull ?? AssetType.other;
              final dm = getDisplayModeForAssetType(assetType);
              final mv = h.quantity * h.currentPrice;
              final totalCost = h.quantity * h.costPrice;
              final pnl = mv - totalCost;
              final pnlPct = totalCost != 0 ? pnl / totalCost * 100 : 0.0;
              final isUp = pnl >= 0;
              return Dismissible(
                key: ValueKey(h.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmDelete(context, ref, h.id, h.assetName),
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
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // 第一行：名称 + 市值/金额
                          Row(
                            children: [
                              // 类型标签
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                child: Text(assetType.code, style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(h.assetName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15), overflow: TextOverflow.ellipsis),
                              ),
                              Text(FormatUtils.formatFullCurrency(mv), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // 第二行：根据类型差异化
                          if (dm == HoldingDisplayMode.deposit) ...[
                            // 存款：只显示类型标签
                            Row(children: [
                              Text(assetType.label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              if (h.assetCode.isNotEmpty && h.assetCode != 'DEPOSIT' && h.assetCode != 'unknown')
                                Text(' · ${h.assetCode}', style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                            ]),
                          ] else if (dm == HoldingDisplayMode.wealth) ...[
                            // 银行理财：总成本 + 收益额
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('投入成本 ${FormatUtils.formatCurrency(totalCost)}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                Text(
                                  '收益 ${pnl >= 0 ? "+" : ""}${FormatUtils.formatCurrency(pnl)}',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isUp ? AppColors.gain : AppColors.loss),
                                ),
                              ],
                            ),
                          ] else if (dm == HoldingDisplayMode.fixedIncome) ...[
                            // 固收基金：代码 + 份额 + 净值 + 收益
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (h.assetCode.isNotEmpty && h.assetCode != 'unknown' && h.assetCode != 'WEALTH')
                                  Text(h.assetCode, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                                if (h.quantity > 1)
                                  Text('${FormatUtils.formatNumber(h.quantity)}份', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                if (h.quantity > 1)
                                  Text('净值 ${h.currentPrice.toStringAsFixed(4)}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                Text(
                                  '收益 ${pnl >= 0 ? "+" : ""}${FormatUtils.formatCurrency(pnl)}',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isUp ? AppColors.gain : AppColors.loss),
                                ),
                              ],
                            ),
                          ] else ...[
                            // 股票/权益基金：代码 + 数量 + 成本→现价 + 盈亏%
                            Row(
                              children: [
                                Text(h.assetCode, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                                const Spacer(),
                                Text('${FormatUtils.formatQuantity(h.quantity)}股', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                const SizedBox(width: 12),
                                Text('${h.costPrice.toStringAsFixed(2)}→${h.currentPrice.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                const SizedBox(width: 8),
                                Text(
                                  FormatUtils.formatPercent(pnlPct),
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isUp ? AppColors.gain : AppColors.loss),
                                ),
                              ],
                            ),
                          ],
                          // 显示关联定投计划
                          Builder(builder: (_) {
                            final linkedPlans = plans.where((p) =>
                              p.assetCode == h.assetCode || p.assetName == h.assetName).toList();
                            if (linkedPlans.isEmpty) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                children: linkedPlans.map((p) {
                                  final freq = InvestFrequency.values.firstWhere(
                                    (f) => f.name == p.frequency, orElse: () => InvestFrequency.monthly);
                                  return Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.event_repeat, size: 12, color: p.isActive ? AppColors.primary : AppColors.textHint),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${freq.label}定投¥${p.amount.toStringAsFixed(0)}',
                                          style: TextStyle(fontSize: 10, color: p.isActive ? AppColors.primary : AppColors.textHint, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          }),
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
        onPressed: () => context.push('/holding-form?accountId=$accountId'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, WidgetRef ref, String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除持仓'),
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
      await db.deleteHolding(id);
      ref.read(autoSyncProvider).triggerAutoSync();
      return true;
    }
    return false;
  }

  Future<void> _aiClassify(BuildContext context, WidgetRef ref) async {
    final holdings = ref.read(holdingsByAccountProvider(accountId)).valueOrNull ?? [];
    if (holdings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无持仓可分类')));
      return;
    }

    final holdingsData = holdings.map((h) => {
      'id': h.id, 'code': h.assetCode, 'name': h.assetName, 'type': h.assetType,
      'quantity': h.quantity, 'currentPrice': h.currentPrice,
    }).toList();

    // 使用流式弹窗实时展示 AI 返回
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _StreamingClassifyDialog(holdingsData: holdingsData),
    );

    if (result == null || !context.mounted) return;

    // 解析结果
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

    // 展示分类结果供确认
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
      final db = ref.read(databaseProvider);
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
    setState(() {
      _content = '';
      _isLoading = true;
      _error = null;
    });

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
      title: Row(
        children: [
          const Text('AI 正在分析分类'),
          if (_isLoading) ...[
            const SizedBox(width: 12),
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ],
      ),
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
                  style: TextStyle(
                    fontSize: 12,
                    color: _content.isEmpty ? AppColors.textHint : AppColors.textPrimary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
