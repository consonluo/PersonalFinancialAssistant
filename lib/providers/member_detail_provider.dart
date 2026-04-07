import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import 'database_provider.dart';

/// 成员的所有持仓（member -> accounts -> holdings）
final memberHoldingsProvider =
    FutureProvider.family<List<Holding>, String>((ref, memberId) async {
  final db = ref.watch(databaseProvider);
  final accounts = await db.getAccountsByMember(memberId);
  final holdings = <Holding>[];
  for (final acc in accounts) {
    holdings.addAll(await db.getHoldingsByAccount(acc.id));
  }
  return holdings;
});

/// 成员的负债
final memberLiabilitiesProvider =
    FutureProvider.family<List<Liability>, String>((ref, memberId) async {
  final db = ref.watch(databaseProvider);
  return db.getLiabilitiesByMember(memberId);
});

/// 成员的定投计划（member -> accounts -> plans）
final memberInvestmentPlansProvider =
    FutureProvider.family<List<InvestmentPlan>, String>((ref, memberId) async {
  final db = ref.watch(databaseProvider);
  final accounts = await db.getAccountsByMember(memberId);
  final plans = <InvestmentPlan>[];
  for (final acc in accounts) {
    plans.addAll(await db.getInvestmentPlansByAccount(acc.id));
  }
  return plans;
});
