import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/database_provider.dart';
import '../../providers/current_role_provider.dart';
import '../../providers/sync_provider.dart';
import '../../data/sync/data_serializer.dart';

class DataManagePage extends ConsumerWidget {
  const DataManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(syncStatusProvider);
    final lastSync = ref.watch(lastSyncTimeProvider);
    final familyId = ref.watch(familyIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('数据管理')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 云端同步状态卡片
          if (familyId != null && familyId.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          syncStatus == SyncStatus.syncing
                              ? Icons.sync
                              : syncStatus == SyncStatus.success
                                  ? Icons.cloud_done
                                  : syncStatus == SyncStatus.error
                                      ? Icons.cloud_off
                                      : Icons.cloud_outlined,
                          color: syncStatus == SyncStatus.error
                              ? AppColors.error
                              : AppColors.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                syncStatus == SyncStatus.syncing
                                    ? '正在同步...'
                                    : syncStatus == SyncStatus.success
                                        ? '同步完成'
                                        : syncStatus == SyncStatus.error
                                            ? '同步失败'
                                            : '云端同步',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (lastSync != null)
                                Text(
                                  '上次同步: ${_formatTime(lastSync)}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: syncStatus == SyncStatus.syncing
                              ? null
                              : () => _manualSync(context, ref),
                          icon: const Icon(Icons.sync, size: 18),
                          label: const Text('立即同步'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _ActionTile(
            icon: Icons.file_upload,
            title: '导出数据到本地',
            subtitle: '将所有数据导出为 JSON 文件保存到本地',
            onTap: () => _export(context, ref),
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.file_download,
            title: '从本地文件导入',
            subtitle: '从 JSON 文件导入（覆盖现有数据）',
            onTap: () => _import(context, ref),
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.delete_forever,
            title: '清空所有数据',
            subtitle: '此操作不可恢复，请谨慎操作',
            color: AppColors.error,
            onTap: () => _clearAll(context, ref),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _manualSync(BuildContext context, WidgetRef ref) async {
    final success = await ref.read(autoSyncProvider).syncUp();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? '同步成功' : '同步失败，请检查网络连接')),
      );
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final db = ref.read(databaseProvider);
      final familyName = ref.read(familyNameProvider);
      final serializer = DataSerializer(db);
      final jsonStr = await serializer.exportToJsonString(familyName);
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));
      final fileName = '${familyName.isEmpty ? "家庭数据" : familyName}.json';

      if (kIsWeb) {
        await FilePicker.platform.saveFile(
          dialogTitle: '导出家庭数据',
          fileName: fileName,
          bytes: bytes,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('数据导出成功')));
        }
      } else {
        final outputPath = await FilePicker.platform.saveFile(
          dialogTitle: '选择导出位置',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: bytes,
        );

        if (context.mounted) {
          if (outputPath != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已导出到: $outputPath')),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;

    try {
      final bytes = result.files.single.bytes!;
      final content = utf8.decode(bytes);
      final data = jsonDecode(content) as Map<String, dynamic>;

      final db = ref.read(databaseProvider);
      await DataSerializer(db).importAll(data);
      ref.read(familyNameProvider.notifier).state = data['familyName'] as String? ?? '我的家庭';

      // 如果有家庭ID，自动触发同步
      ref.read(autoSyncProvider).triggerAutoSync();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('数据导入成功')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
      }
    }
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('此操作将删除所有数据，无法恢复。确定继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认清空', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final db = ref.read(databaseProvider);
    await db.clearAllData();

    // 立即同步空数据到云端（确保其他端也看到删除结果）
    try { await ref.read(autoSyncProvider).syncUp(); } catch (_) {}

    ref.read(familyNameProvider.notifier).state = '';
    ref.read(isDemoModeProvider.notifier).state = false;
    await ref.read(familyIdProvider.notifier).clearFamilyId();
    await ref.read(currentRoleProvider.notifier).clearRole();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('所有数据已清空')));
      context.go('/welcome');
    }
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? color;
  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: c),
        title: Text(title, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
