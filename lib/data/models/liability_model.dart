import '../../core/constants/app_constants.dart';

/// 负债模型
class LiabilityModel {
  final String id;
  final String memberId;
  final LiabilityType type;
  final String name;
  final double totalAmount;
  final double remainingAmount;
  final double interestRate;
  final double monthlyPayment;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LiabilityModel({
    required this.id,
    required this.memberId,
    required this.type,
    required this.name,
    this.totalAmount = 0,
    this.remainingAmount = 0,
    this.interestRate = 0,
    this.monthlyPayment = 0,
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory LiabilityModel.fromJson(Map<String, dynamic> json) {
    return LiabilityModel(
      id: json['id'] as String,
      memberId: json['memberId'] as String,
      type: LiabilityType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => LiabilityType.other,
      ),
      name: json['name'] as String,
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
      remainingAmount: (json['remainingAmount'] as num?)?.toDouble() ?? 0,
      interestRate: (json['interestRate'] as num?)?.toDouble() ?? 0,
      monthlyPayment: (json['monthlyPayment'] as num?)?.toDouble() ?? 0,
      notes: json['notes'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'memberId': memberId,
        'type': type.name,
        'name': name,
        'totalAmount': totalAmount,
        'remainingAmount': remainingAmount,
        'interestRate': interestRate,
        'monthlyPayment': monthlyPayment,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  LiabilityModel copyWith({
    String? id,
    String? memberId,
    LiabilityType? type,
    String? name,
    double? totalAmount,
    double? remainingAmount,
    double? interestRate,
    double? monthlyPayment,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LiabilityModel(
      id: id ?? this.id,
      memberId: memberId ?? this.memberId,
      type: type ?? this.type,
      name: name ?? this.name,
      totalAmount: totalAmount ?? this.totalAmount,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      interestRate: interestRate ?? this.interestRate,
      monthlyPayment: monthlyPayment ?? this.monthlyPayment,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
