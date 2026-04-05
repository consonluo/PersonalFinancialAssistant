import 'package:drift/drift.dart';

/// 资产快照表 - 记录每日资产数据用于走势图
class AssetSnapshots extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get snapshotDate => dateTime()();
  RealColumn get totalAssets => real().withDefault(const Constant(0))();
  RealColumn get totalLiabilities => real().withDefault(const Constant(0))();
  RealColumn get netWorth => real().withDefault(const Constant(0))();
  RealColumn get totalFixedAssets => real().withDefault(const Constant(0))();
  TextColumn get categoryBreakdown => text().withDefault(const Constant('{}'))(); // JSON: {type: value}
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
