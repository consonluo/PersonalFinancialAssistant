import 'package:drift/drift.dart';

/// 账户表
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get memberId => text()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get type => text()(); // AccountType enum name
  TextColumn get institution => text().withDefault(const Constant(''))();
  TextColumn get subType =>
      text().withDefault(const Constant(''))(); // AccountSubType
  RealColumn get financingAmount =>
      real().withDefault(const Constant(0.0))(); // 融资负债金额
  TextColumn get financingCurrency =>
      text().withDefault(const Constant('CNY'))(); // 融资负债币种
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
