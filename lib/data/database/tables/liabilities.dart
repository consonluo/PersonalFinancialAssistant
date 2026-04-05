import 'package:drift/drift.dart';

/// 负债表
class Liabilities extends Table {
  TextColumn get id => text()();
  TextColumn get memberId => text()();
  TextColumn get type => text()(); // LiabilityType enum name
  TextColumn get name => text()();
  RealColumn get totalAmount => real().withDefault(const Constant(0))();
  RealColumn get remainingAmount => real().withDefault(const Constant(0))();
  RealColumn get interestRate => real().withDefault(const Constant(0))(); // 年化利率 %
  RealColumn get monthlyPayment => real().withDefault(const Constant(0))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
