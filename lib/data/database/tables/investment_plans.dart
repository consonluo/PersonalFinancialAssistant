import 'package:drift/drift.dart';

/// 定投计划表
class InvestmentPlans extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get assetCode => text()();
  TextColumn get assetName => text()();
  RealColumn get amount => real().withDefault(const Constant(0))();
  TextColumn get frequency => text()(); // InvestFrequency enum name
  DateTimeColumn get nextDate => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
