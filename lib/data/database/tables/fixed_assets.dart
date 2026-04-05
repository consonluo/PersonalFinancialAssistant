import 'package:drift/drift.dart';

/// 固定资产表
class FixedAssets extends Table {
  TextColumn get id => text()();
  TextColumn get memberId => text()();
  TextColumn get type => text()(); // realEstate / vehicle
  TextColumn get name => text()();
  RealColumn get estimatedValue => real().withDefault(const Constant(0))();
  TextColumn get details => text().withDefault(const Constant('{}'))(); // JSON: address, area, etc.
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
