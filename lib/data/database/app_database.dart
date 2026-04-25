import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/family_members.dart';
import 'tables/accounts.dart';
import 'tables/holdings.dart';
import 'tables/fixed_assets.dart';
import 'tables/liabilities.dart';
import 'tables/investment_plans.dart';
import 'tables/market_cache.dart';
import 'tables/asset_snapshots.dart';

part 'app_database.g.dart';

// Web 端 Drift 数据库配置

@DriftDatabase(tables: [
  FamilyMembers,
  Accounts,
  Holdings,
  FixedAssets,
  Liabilities,
  InvestmentPlans,
  MarketCache,
  AssetSnapshots,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.createTable(assetSnapshots);
        }
        if (from < 3) {
          // 添加 currency 字段到 holdings 表
          await m.addColumn(holdings, holdings.currency);
        }
      },
    );
  }

  // ===== Family Members =====
  Future<List<FamilyMember>> getAllMembers() => select(familyMembers).get();
  Stream<List<FamilyMember>> watchAllMembers() => select(familyMembers).watch();
  Future<FamilyMember?> getMemberById(String id) =>
      (select(familyMembers)..where((t) => t.id.equals(id))).getSingleOrNull();
  Future<int> insertMember(FamilyMembersCompanion entry) =>
      into(familyMembers).insert(entry);
  Future<bool> updateMember(FamilyMembersCompanion entry) =>
      update(familyMembers).replace(entry);
  Future<int> deleteMember(String id) =>
      (delete(familyMembers)..where((t) => t.id.equals(id))).go();

  // ===== Accounts =====
  Future<List<Account>> getAllAccounts() => select(accounts).get();
  Stream<List<Account>> watchAllAccounts() => select(accounts).watch();
  Future<List<Account>> getAccountsByMember(String memberId) =>
      (select(accounts)..where((t) => t.memberId.equals(memberId))).get();
  Stream<List<Account>> watchAccountsByMember(String memberId) =>
      (select(accounts)..where((t) => t.memberId.equals(memberId))).watch();
  Future<Account?> getAccountById(String id) =>
      (select(accounts)..where((t) => t.id.equals(id))).getSingleOrNull();
  Future<int> insertAccount(AccountsCompanion entry) =>
      into(accounts).insert(entry);
  Future<bool> updateAccount(AccountsCompanion entry) =>
      update(accounts).replace(entry);
  Future<int> deleteAccount(String id) =>
      (delete(accounts)..where((t) => t.id.equals(id))).go();

  // ===== Holdings =====
  Future<List<Holding>> getAllHoldings() => select(holdings).get();
  Stream<List<Holding>> watchAllHoldings() => select(holdings).watch();
  Future<List<Holding>> getHoldingsByAccount(String accountId) =>
      (select(holdings)..where((t) => t.accountId.equals(accountId))).get();
  Stream<List<Holding>> watchHoldingsByAccount(String accountId) =>
      (select(holdings)..where((t) => t.accountId.equals(accountId))).watch();
  Future<Holding?> getHoldingById(String id) =>
      (select(holdings)..where((t) => t.id.equals(id))).getSingleOrNull();
  Future<int> insertHolding(HoldingsCompanion entry) =>
      into(holdings).insert(entry);
  Future<bool> updateHolding(HoldingsCompanion entry) =>
      update(holdings).replace(entry);
  Future<int> deleteHolding(String id) =>
      (delete(holdings)..where((t) => t.id.equals(id))).go();
  Future<void> insertHoldingsBatch(List<HoldingsCompanion> entries) async {
    await batch((b) => b.insertAll(holdings, entries));
  }

  // ===== Fixed Assets =====
  Future<List<FixedAsset>> getAllFixedAssets() => select(fixedAssets).get();
  Stream<List<FixedAsset>> watchAllFixedAssets() => select(fixedAssets).watch();
  Future<List<FixedAsset>> getFixedAssetsByMember(String memberId) =>
      (select(fixedAssets)..where((t) => t.memberId.equals(memberId))).get();
  Future<int> insertFixedAsset(FixedAssetsCompanion entry) =>
      into(fixedAssets).insert(entry);
  Future<bool> updateFixedAsset(FixedAssetsCompanion entry) =>
      update(fixedAssets).replace(entry);
  Future<int> deleteFixedAsset(String id) =>
      (delete(fixedAssets)..where((t) => t.id.equals(id))).go();

  // ===== Liabilities =====
  Future<List<Liability>> getAllLiabilities() => select(liabilities).get();
  Stream<List<Liability>> watchAllLiabilities() => select(liabilities).watch();
  Future<List<Liability>> getLiabilitiesByMember(String memberId) =>
      (select(liabilities)..where((t) => t.memberId.equals(memberId))).get();
  Future<int> insertLiability(LiabilitiesCompanion entry) =>
      into(liabilities).insert(entry);
  Future<bool> updateLiability(LiabilitiesCompanion entry) =>
      update(liabilities).replace(entry);
  Future<int> deleteLiability(String id) =>
      (delete(liabilities)..where((t) => t.id.equals(id))).go();

  // ===== Investment Plans =====
  Future<List<InvestmentPlan>> getAllInvestmentPlans() =>
      select(investmentPlans).get();
  Stream<List<InvestmentPlan>> watchAllInvestmentPlans() =>
      select(investmentPlans).watch();
  Future<List<InvestmentPlan>> getInvestmentPlansByAccount(String accountId) =>
      (select(investmentPlans)..where((t) => t.accountId.equals(accountId)))
          .get();
  Future<int> insertInvestmentPlan(InvestmentPlansCompanion entry) =>
      into(investmentPlans).insert(entry);
  Future<bool> updateInvestmentPlan(InvestmentPlansCompanion entry) =>
      update(investmentPlans).replace(entry);
  Future<int> deleteInvestmentPlan(String id) =>
      (delete(investmentPlans)..where((t) => t.id.equals(id))).go();

  // ===== Market Cache =====
  Future<List<MarketCacheData>> getAllMarketCache() =>
      select(marketCache).get();
  Future<MarketCacheData?> getMarketCacheByCode(String code) =>
      (select(marketCache)..where((t) => t.assetCode.equals(code)))
          .getSingleOrNull();
  Future<int> upsertMarketCache(MarketCacheCompanion entry) =>
      into(marketCache).insertOnConflictUpdate(entry);
  Future<void> upsertMarketCacheBatch(List<MarketCacheCompanion> entries) async {
    await batch((b) {
      for (final entry in entries) {
        b.insert(marketCache, entry, onConflict: DoUpdate((_) => entry));
      }
    });
  }

  // ===== Asset Snapshots =====
  Future<List<AssetSnapshot>> getAllSnapshots() =>
      (select(assetSnapshots)..orderBy([(t) => OrderingTerm.asc(t.snapshotDate)])).get();
  Future<List<AssetSnapshot>> getSnapshotsByDateRange(DateTime start, DateTime end) =>
      (select(assetSnapshots)
        ..where((t) => t.snapshotDate.isBiggerOrEqualValue(start) & t.snapshotDate.isSmallerOrEqualValue(end))
        ..orderBy([(t) => OrderingTerm.asc(t.snapshotDate)]))
          .get();
  Future<AssetSnapshot?> getSnapshotByDate(DateTime date) async {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final results = await (select(assetSnapshots)
      ..where((t) => t.snapshotDate.isBiggerOrEqualValue(dayStart) & t.snapshotDate.isSmallerThanValue(dayEnd))
      ..orderBy([(t) => OrderingTerm.desc(t.id)]))
        .get();
    return results.firstOrNull;
  }
  Future<int> insertSnapshot(AssetSnapshotsCompanion entry) =>
      into(assetSnapshots).insert(entry);
  Future<void> deleteOldSnapshots(DateTime before) =>
      (delete(assetSnapshots)..where((t) => t.snapshotDate.isSmallerThanValue(before))).go();
  Future<void> deleteSnapshotById(int id) =>
      (delete(assetSnapshots)..where((t) => t.id.equals(id))).go();

  // ===== Utility =====
  Future<void> clearAllData() async {
    await delete(familyMembers).go();
    await delete(accounts).go();
    await delete(holdings).go();
    await delete(fixedAssets).go();
    await delete(liabilities).go();
    await delete(investmentPlans).go();
    await delete(marketCache).go();
    await delete(assetSnapshots).go();
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'family_finance',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
}
