import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import 'database_provider.dart';

/// 家庭成员列表 Provider (Stream)
final familyMembersProvider = StreamProvider<List<FamilyMember>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllMembers();
});

/// 单个成员 Provider
final memberByIdProvider =
    FutureProvider.family<FamilyMember?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  return db.getMemberById(id);
});
