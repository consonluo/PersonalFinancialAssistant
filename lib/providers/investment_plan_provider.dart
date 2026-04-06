import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import 'database_provider.dart';

/// 所有定投计划 Provider
final allInvestmentPlansProvider = StreamProvider<List<InvestmentPlan>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllInvestmentPlans();
});

/// 按账户筛选的定投计划
final investmentPlansByAccountProvider =
    FutureProvider.family<List<InvestmentPlan>, String>((ref, accountId) async {
  final db = ref.watch(databaseProvider);
  return db.getInvestmentPlansByAccount(accountId);
});
