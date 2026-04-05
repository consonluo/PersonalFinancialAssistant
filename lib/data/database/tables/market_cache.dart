import 'package:drift/drift.dart';

/// 行情缓存表
class MarketCache extends Table {
  TextColumn get assetCode => text()();
  RealColumn get price => real().withDefault(const Constant(0))();
  RealColumn get change => real().withDefault(const Constant(0))();
  RealColumn get changePercent => real().withDefault(const Constant(0))();
  RealColumn get volume => real().withDefault(const Constant(0))();
  TextColumn get name => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {assetCode};
}
