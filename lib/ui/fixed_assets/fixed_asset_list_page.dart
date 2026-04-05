import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format_utils.dart';
import '../../providers/database_provider.dart';
import '../../providers/sync_provider.dart';
import '../../data/database/app_database.dart';

/// 固定资产 Provider
final allFixedAssetsProvider = StreamProvider<List<FixedAsset>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllFixedAssets();
});

class FixedAssetListPage extends ConsumerWidget {
  const FixedAssetListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetsAsync = ref.watch(allFixedAssetsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('其他资产')),
      body: assetsAsync.when(
        data: (assets) {
          if (assets.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.home_outlined, size: 48, color: AppColors.textHint),
                  const SizedBox(height: 12),
                  const Text('暂无其他资产', style: TextStyle(color: AppColors.textHint)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/fixed-asset-form'),
                    icon: const Icon(Icons.add),
                    label: const Text('添加资产'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: assets.length,
            itemBuilder: (context, index) {
              final a = assets[index];
              final icon = a.type == 'realEstate' ? Icons.home : a.type == 'vehicle' ? Icons.directions_car : Icons.category;
              final typeLabel = a.type == 'realEstate' ? '房产' : a.type == 'vehicle' ? '车辆' : '其他';
              return Dismissible(
                key: ValueKey(a.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmDelete(context, ref, a.id, a.name),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: AppColors.error,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: AppColors.primary),
                    ),
                    title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(typeLabel, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    trailing: Text(
                      FormatUtils.formatCurrency(a.estimatedValue),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    onTap: () => context.push('/fixed-asset-form?id=${a.id}'),
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
        onPressed: () => context.push('/fixed-asset-form'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, WidgetRef ref, String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除资产'),
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
      await db.deleteFixedAsset(id);
      ref.read(autoSyncProvider).triggerAutoSync();
      return true;
    }
    return false;
  }
}
