import 'dart:convert';
import 'package:drift/drift.dart';
import '../../data/database/app_database.dart';

/// 资产快照服务 - 记录每日资产数据
class SnapshotService {
  final AppDatabase db;

  SnapshotService(this.db);

  /// 记录/更新今日资产快照
  /// 如果今天已有快照但金额为0或数据有变化，会重新计算并覆盖
  Future<void> takeSnapshotIfNeeded() async {
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
      // 如果今天已有快照，但总资产为0或与当前计算值偏差超过1%，则覆盖更新
      final needsUpdate = existing.totalAssets == 0 ||
          (totalAssets > 0 && (existing.totalAssets - totalAssets).abs() / totalAssets > 0.01);
      if (!needsUpdate) return; // 数据没变化，不更新

      // 删除旧快照再插入新的
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
