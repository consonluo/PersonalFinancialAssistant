/// 同步配置模型（简化版：仅保存 familyId 和同步时间）
class SyncConfigModel {
  final String? familyId;
  final DateTime? lastSyncTime;

  const SyncConfigModel({
    this.familyId,
    this.lastSyncTime,
  });

  bool get isConfigured => familyId != null && familyId!.isNotEmpty;

  factory SyncConfigModel.fromJson(Map<String, dynamic> json) {
    return SyncConfigModel(
      familyId: json['familyId'] as String?,
      lastSyncTime: json['lastSyncTime'] != null
          ? DateTime.parse(json['lastSyncTime'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'familyId': familyId,
        'lastSyncTime': lastSyncTime?.toIso8601String(),
      };

  SyncConfigModel copyWith({
    String? familyId,
    DateTime? lastSyncTime,
  }) {
    return SyncConfigModel(
      familyId: familyId ?? this.familyId,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}

/// 家庭数据文件模型（完整导入导出用）
class FamilyDataModel {
  final String familyName;
  final int version;
  final DateTime exportedAt;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> holdings;
  final List<Map<String, dynamic>> fixedAssets;
  final List<Map<String, dynamic>> liabilities;
  final List<Map<String, dynamic>> investmentPlans;

  const FamilyDataModel({
    required this.familyName,
    this.version = 1,
    required this.exportedAt,
    this.members = const [],
    this.accounts = const [],
    this.holdings = const [],
    this.fixedAssets = const [],
    this.liabilities = const [],
    this.investmentPlans = const [],
  });

  factory FamilyDataModel.fromJson(Map<String, dynamic> json) {
    return FamilyDataModel(
      familyName: json['familyName'] as String? ?? '',
      version: json['version'] as int? ?? 1,
      exportedAt: json['exportedAt'] != null
          ? DateTime.parse(json['exportedAt'] as String)
          : DateTime.now(),
      members: (json['members'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      accounts:
          (json['accounts'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      holdings:
          (json['holdings'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      fixedAssets:
          (json['fixedAssets'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      liabilities:
          (json['liabilities'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      investmentPlans:
          (json['investmentPlans'] as List?)?.cast<Map<String, dynamic>>() ??
              [],
    );
  }

  Map<String, dynamic> toJson() => {
        'familyName': familyName,
        'version': version,
        'exportedAt': exportedAt.toIso8601String(),
        'members': members,
        'accounts': accounts,
        'holdings': holdings,
        'fixedAssets': fixedAssets,
        'liabilities': liabilities,
        'investmentPlans': investmentPlans,
      };
}
