import 'dart:convert';
import 'package:drift/drift.dart';
import '../../data/database/app_database.dart';

/// 资产快照服务 - 记录每日资产数据
class SnapshotService {
  final AppDatabase db;

  SnapshotService(this.db);

  /// 记录/更新今日资产快照
  ///
  /// [forceUpdateToday] 为 true 时：只要今日已有快照则一律用当前持仓/负债重算并覆盖
  /// （用于行情接口成功拉取到最新净值/现价后，把当日资产总额写进走势图）
  /// 默认 false：仅在无今日快照、或总资为 0、或与当前值偏差超过 1% 时更新
  Future<void> takeSnapshotIfNeeded({bool forceUpdateToday = false}) async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final existing = await db.getSnapshotByDate(today);

    // 计算投资资产总额
    final holdings = await db.getAllHoldings();
    double totalInvestment = 0;
    final categoryMap = <String, double>{};

    for (final h in holdings) {
      if (h.quantity == 0) continue; // 跳过已清仓的
      final mv = h.quantity * h.currentPrice;
      totalInvestment += mv;
      final type = h.assetType;
      categoryMap[type] = (categoryMap[type] ?? 0) + mv;
    }

    // 计算固定资产
    final fixedAssets = await db.getAllFixedAssets();
    double totalFixed = 0;
    for (final a in fixedAssets) {
      totalFixed += a.estimatedValue;
      categoryMap[a.type] = (categoryMap[a.type] ?? 0) + a.estimatedValue;
    }

    // 计算负债
    final liabilities = await db.getAllLiabilities();
    double totalLiability = 0;
    for (final l in liabilities) {
      totalLiability += l.remainingAmount;
    }

    final totalAssets = totalInvestment + totalFixed;
    final netWorth = totalAssets - totalLiability;

    if (existing != null) {
      if (!forceUpdateToday) {
        final needsUpdate = existing.totalAssets == 0 ||
            (totalAssets > 0 && (existing.totalAssets - totalAssets).abs() / totalAssets > 0.01);
        if (!needsUpdate) return;
      }
      await db.deleteSnapshotById(existing.id);
    }

    await db.insertSnapshot(AssetSnapshotsCompanion(
      snapshotDate: Value(todayDate),
      totalAssets: Value(totalAssets),
      totalLiabilities: Value(totalLiability),
      netWorth: Value(netWorth),
      totalFixedAssets: Value(totalFixed),
      categoryBreakdown: Value(jsonEncode(categoryMap)),
      createdAt: Value(DateTime.now()),
    ));
  }
}
