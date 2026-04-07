import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import '../core/utils/snapshot_service.dart';
import 'database_provider.dart';

/// 资产快照数据 Provider（全局共享）
final snapshotListProvider = FutureProvider<List<AssetSnapshot>>((ref) async {
  final db = ref.watch(databaseProvider);
  await SnapshotService(db).takeSnapshotIfNeeded();
  return db.getAllSnapshots();
});
