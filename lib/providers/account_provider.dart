import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import 'database_provider.dart';

/// 所有账户列表 Provider
final allAccountsProvider = StreamProvider<List<Account>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllAccounts();
});

/// 按成员筛选的账户列表
final accountsByMemberProvider =
    StreamProvider.family<List<Account>, String>((ref, memberId) {
  final db = ref.watch(databaseProvider);
  return db.watchAccountsByMember(memberId);
});

/// 单个账户 Provider
final accountByIdProvider =
    FutureProvider.family<Account?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  return db.getAccountById(id);
});
