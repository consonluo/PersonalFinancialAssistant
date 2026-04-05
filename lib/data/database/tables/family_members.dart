import 'package:drift/drift.dart';

/// 家庭成员表
class FamilyMembers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get avatar => text().withDefault(const Constant(''))();
  TextColumn get role => text()(); // FamilyRole enum name
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
