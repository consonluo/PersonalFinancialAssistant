import '../../core/constants/app_constants.dart';

/// 账户模型
class AccountModel {
  final String id;
  final String memberId;
  final String name;
  final AccountType type;
  final String institution;
  final AccountSubType? subType;
  final double financingAmount;
  final String financingCurrency;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AccountModel({
    required this.id,
    required this.memberId,
    required this.name,
    required this.type,
    this.institution = '',
    this.subType,
    this.financingAmount = 0,
    this.financingCurrency = 'CNY',
    required this.createdAt,
    required this.updatedAt,
  });

  factory AccountModel.fromJson(Map<String, dynamic> json) {
    return AccountModel(
      id: json['id'] as String,
      memberId: json['memberId'] as String,
      name: json['name'] as String,
      type: AccountType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => AccountType.bank,
      ),
      institution: json['institution'] as String? ?? '',
      subType: json['subType'] != null && (json['subType'] as String).isNotEmpty
          ? AccountSubType.values.firstWhere(
              (e) => e.name == json['subType'],
              orElse: () => AccountSubType.checking,
            )
          : null,
      financingAmount: (json['financingAmount'] as num?)?.toDouble() ?? 0,
      financingCurrency: json['financingCurrency'] as String? ?? 'CNY',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'memberId': memberId,
        'name': name,
        'type': type.name,
        'institution': institution,
        'subType': subType?.name ?? '',
        'financingAmount': financingAmount,
        'financingCurrency': financingCurrency,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  AccountModel copyWith({
    String? id,
    String? memberId,
    String? name,
    AccountType? type,
    String? institution,
    AccountSubType? subType,
    double? financingAmount,
    String? financingCurrency,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AccountModel(
      id: id ?? this.id,
      memberId: memberId ?? this.memberId,
      name: name ?? this.name,
      type: type ?? this.type,
      institution: institution ?? this.institution,
      subType: subType ?? this.subType,
      financingAmount: financingAmount ?? this.financingAmount,
      financingCurrency: financingCurrency ?? this.financingCurrency,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
