import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/ai_service.dart';
import '../../providers/account_provider.dart';
import '../../providers/family_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/sync_provider.dart';
import '../../data/database/app_database.dart';

class AccountListPage extends ConsumerWidget {
  const AccountListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(allAccountsProvider);
    final membersAsync = ref.watch(familyMembersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('账户管理')),
      body: accountsAsync.when(
        data: (accounts) {
          if (accounts.isEmpty) {
            return const Center(child: Text('暂无账户'));
          }
          final members = membersAsync.valueOrNull ?? [];
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: accounts.length,
            itemBuilder: (context, index) {
              final acc = accounts[index];
              final memberName = members.where((m) => m.id == acc.memberId).firstOrNull?.name ?? '';
              return Dismissible(
                key: ValueKey(acc.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmDeleteAccount(context, ref, acc.id, acc.name),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: AppColors.error,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      acc.type == 'securities' ? Icons.trending_up : Icons.account_balance,
                      color: AppColors.primary,
                    ),
                    title: Text(acc.name),
                    subtitle: Text('$memberName · ${acc.institution}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.auto_awesome, size: 20, color: AppColors.info),
                          tooltip: 'AI 智能分类',
                          onPressed: () => _aiClassifyAccount(context, ref, acc.id),
                        ),
                        const Icon(Icons.chevron_right, color: AppColors.textHint),
                      ],
                    ),
                    onTap: () => context.push('/holdings?accountId=${acc.id}'),
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
        onPressed: () => context.push('/account-form'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<bool> _confirmDeleteAccount(BuildContext context, WidgetRef ref, String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账户'),
        content: Text('确定删除「$name」？\n该账户下的所有持仓也会一并删除。'),
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
      final holdings = await db.getHoldingsByAccount(id);
      for (final h in holdings) {
        await db.deleteHolding(h.id);
      }
      await db.deleteAccount(id);
      ref.read(autoSyncProvider).triggerAutoSync();
      return true;
    }
    return false;
  }

  Future<void> _aiClassifyAccount(BuildContext context, WidgetRef ref, String accountId) async {
    final db = ref.read(databaseProvider);
    final holdings = await db.getHoldingsByAccount(accountId);
    if (holdings.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('该账户暂无持仓可分类')));
      }
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
