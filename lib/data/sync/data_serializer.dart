import 'dart:convert';
import '../database/app_database.dart';
import 'package:drift/drift.dart';

/// 数据序列化器：SQLite 全量数据 ↔ JSON
class DataSerializer {
  final AppDatabase db;

  DataSerializer(this.db);

  /// 导出所有数据为 JSON
  Future<Map<String, dynamic>> exportAll(String familyName) async {
    final members = await db.getAllMembers();
    final accounts = await db.getAllAccounts();
    final holdings = await db.getAllHoldings();
    final fixedAssets = await db.getAllFixedAssets();
    final liabilities = await db.getAllLiabilities();
    final plans = await db.getAllInvestmentPlans();

    return {
      'familyName': familyName,
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'members': members.map((m) => {
        'id': m.id, 'name': m.name, 'avatar': m.avatar,
        'role': m.role, 'createdAt': m.createdAt.toIso8601String(),
        'updatedAt': m.updatedAt.toIso8601String(),
      }).toList(),
      'accounts': accounts.map((a) => {
        'id': a.id, 'memberId': a.memberId, 'name': a.name,
        'type': a.type, 'institution': a.institution, 'subType': a.subType,
        'createdAt': a.createdAt.toIso8601String(),
        'updatedAt': a.updatedAt.toIso8601String(),
      }).toList(),
      'holdings': holdings.map((h) => {
        'id': h.id, 'accountId': h.accountId, 'assetCode': h.assetCode,
        'assetName': h.assetName, 'assetType': h.assetType,
        'quantity': h.quantity, 'costPrice': h.costPrice,
        'currentPrice': h.currentPrice, 'tags': h.tags, 'notes': h.notes,
        'createdAt': h.createdAt.toIso8601String(),
        'updatedAt': h.updatedAt.toIso8601String(),
      }).toList(),
      'fixedAssets': fixedAssets.map((f) => {
        'id': f.id, 'memberId': f.memberId, 'type': f.type,
        'name': f.name, 'estimatedValue': f.estimatedValue,
        'details': f.details, 'notes': f.notes,
        'createdAt': f.createdAt.toIso8601String(),
        'updatedAt': f.updatedAt.toIso8601String(),
      }).toList(),
      'liabilities': liabilities.map((l) => {
        'id': l.id, 'memberId': l.memberId, 'type': l.type,
        'name': l.name, 'totalAmount': l.totalAmount,
        'remainingAmount': l.remainingAmount,
        'interestRate': l.interestRate,
        'monthlyPayment': l.monthlyPayment, 'notes': l.notes,
        'createdAt': l.createdAt.toIso8601String(),
        'updatedAt': l.updatedAt.toIso8601String(),
      }).toList(),
      'investmentPlans': plans.map((p) => {
        'id': p.id, 'accountId': p.accountId, 'assetCode': p.assetCode,
        'assetName': p.assetName, 'amount': p.amount,
        'frequency': p.frequency,
        'nextDate': p.nextDate?.toIso8601String(),
        'isActive': p.isActive,
        'createdAt': p.createdAt.toIso8601String(),
      }).toList(),
    };
  }

  /// 导入 JSON 数据到数据库（清空后导入）
  Future<void> importAll(Map<String, dynamic> data) async {
    await db.clearAllData();

    // 导入成员
    for (final m in (data['members'] as List? ?? [])) {
      await db.insertMember(FamilyMembersCompanion(
        id: Value(m['id'] as String),
        name: Value(m['name'] as String),
        avatar: Value(m['avatar'] as String? ?? ''),
        role: Value(m['role'] as String? ?? 'other'),
        createdAt: Value(DateTime.parse(m['createdAt'] as String)),
        updatedAt: Value(DateTime.parse(m['updatedAt'] as String)),
      ));
    }

    // 导入账户
    for (final a in (data['accounts'] as List? ?? [])) {
      await db.insertAccount(AccountsCompanion(
        id: Value(a['id'] as String),
        memberId: Value(a['memberId'] as String),
        name: Value(a['name'] as String),
        type: Value(a['type'] as String),
        institution: Value(a['institution'] as String? ?? ''),
        subType: Value(a['subType'] as String? ?? ''),
        createdAt: Value(DateTime.parse(a['createdAt'] as String)),
        updatedAt: Value(DateTime.parse(a['updatedAt'] as String)),
      ));
    }

    // 导入持仓
    for (final h in (data['holdings'] as List? ?? [])) {
      await db.insertHolding(HoldingsCompanion(
        id: Value(h['id'] as String),
        accountId: Value(h['accountId'] as String),
        assetCode: Value(h['assetCode'] as String),
        assetName: Value(h['assetName'] as String),
        assetType: Value(h['assetType'] as String),
        quantity: Value((h['quantity'] as num).toDouble()),
        costPrice: Value((h['costPrice'] as num).toDouble()),
        currentPrice: Value((h['currentPrice'] as num).toDouble()),
        tags: Value(h['tags'] is List ? jsonEncode(h['tags']) : h['tags'] as String? ?? ''),
        notes: Value(h['notes'] as String? ?? ''),
        createdAt: Value(DateTime.parse(h['createdAt'] as String)),
        updatedAt: Value(DateTime.parse(h['updatedAt'] as String)),
      ));
    }

    // 导入固定资产
    for (final f in (data['fixedAssets'] as List? ?? [])) {
      await db.insertFixedAsset(FixedAssetsCompanion(
        id: Value(f['id'] as String),
        memberId: Value(f['memberId'] as String),
        type: Value(f['type'] as String),
        name: Value(f['name'] as String),
        estimatedValue: Value((f['estimatedValue'] as num).toDouble()),
        details: Value(f['details'] as String? ?? '{}'),
        notes: Value(f['notes'] as String? ?? ''),
        createdAt: Value(DateTime.parse(f['createdAt'] as String)),
        updatedAt: Value(DateTime.parse(f['updatedAt'] as String)),
      ));
    }

    // 导入负债
    for (final l in (data['liabilities'] as List? ?? [])) {
      await db.insertLiability(LiabilitiesCompanion(
        id: Value(l['id'] as String),
        memberId: Value(l['memberId'] as String),
        type: Value(l['type'] as String),
        name: Value(l['name'] as String),
        totalAmount: Value((l['totalAmount'] as num).toDouble()),
        remainingAmount: Value((l['remainingAmount'] as num).toDouble()),
        interestRate: Value((l['interestRate'] as num).toDouble()),
        monthlyPayment: Value((l['monthlyPayment'] as num).toDouble()),
        notes: Value(l['notes'] as String? ?? ''),
        createdAt: Value(DateTime.parse(l['createdAt'] as String)),
        updatedAt: Value(DateTime.parse(l['updatedAt'] as String)),
      ));
    }

    // 导入定投计划
    for (final p in (data['investmentPlans'] as List? ?? [])) {
      await db.insertInvestmentPlan(InvestmentPlansCompanion(
        id: Value(p['id'] as String),
        accountId: Value(p['accountId'] as String),
        assetCode: Value(p['assetCode'] as String),
        assetName: Value(p['assetName'] as String),
        amount: Value((p['amount'] as num).toDouble()),
        frequency: Value(p['frequency'] as String),
        nextDate: Value(p['nextDate'] != null ? DateTime.parse(p['nextDate'] as String) : null),
        isActive: Value(p['isActive'] as bool? ?? true),
        createdAt: Value(DateTime.parse(p['createdAt'] as String)),
      ));
    }
  }

  /// 导出为 JSON 字符串
  Future<String> exportToJsonString(String familyName) async {
    final data = await exportAll(familyName);
    return const JsonEncoder.withIndent('  ').convert(data);
  }
}
