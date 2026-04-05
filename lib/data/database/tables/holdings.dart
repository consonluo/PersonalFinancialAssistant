import 'package:drift/drift.dart';

/// 持仓表
class Holdings extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get assetCode => text()();
  TextColumn get assetName => text()();
  TextColumn get assetType => text()(); // AssetType enum name
  RealColumn get quantity => real().withDefault(const Constant(0))();
  RealColumn get costPrice => real().withDefault(const Constant(0))();
  RealColumn get currentPrice => real().withDefault(const Constant(0))();
  TextColumn get tags => text().withDefault(const Constant(''))(); // JSON array string
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
