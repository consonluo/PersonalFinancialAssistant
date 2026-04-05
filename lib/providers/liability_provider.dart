import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import 'database_provider.dart';

/// 所有负债 Provider
final allLiabilitiesProvider = StreamProvider<List<Liability>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllLiabilities();
});

/// 总负债金额
final totalLiabilityProvider = Provider<double>((ref) {
  final liabilities = ref.watch(allLiabilitiesProvider).valueOrNull ?? [];
  return liabilities.fold(0.0, (sum, l) => sum + l.remainingAmount);
});
