import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import 'database_provider.dart';

/// 所有持仓 Provider（过滤掉持仓量为 0 的记录）
final allHoldingsProvider = StreamProvider<List<Holding>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllHoldings().map(
    (list) => list.where((h) => h.quantity != 0).toList(),
  );
});

/// 按账户筛选的持仓（过滤掉持仓量为 0 的记录）
final holdingsByAccountProvider =
    StreamProvider.family<List<Holding>, String>((ref, accountId) {
  final db = ref.watch(databaseProvider);
  return db.watchHoldingsByAccount(accountId).map(
    (list) => list.where((h) => h.quantity != 0).toList(),
  );
});
