import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import 'database_provider.dart';

/// 所有持仓 Provider
final allHoldingsProvider = StreamProvider<List<Holding>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllHoldings();
});

/// 按账户筛选的持仓
final holdingsByAccountProvider =
    StreamProvider.family<List<Holding>, String>((ref, accountId) {
  final db = ref.watch(databaseProvider);
  return db.watchHoldingsByAccount(accountId);
});
