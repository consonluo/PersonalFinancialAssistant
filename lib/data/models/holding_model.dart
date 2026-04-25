import 'dart:convert';
import '../../core/constants/app_constants.dart';

/// 持仓模型
class HoldingModel {
  final String id;
  final String accountId;
  final String assetCode;
  final String assetName;
  final AssetType assetType;
  final double quantity;
  final double costPrice;
  final double currentPrice;
  final List<String> tags;
  final String notes;
  final String currency; // 币种: CNY/HKD/USD/EUR/GBP
  final DateTime createdAt;
  final DateTime updatedAt;

  const HoldingModel({
    required this.id,
    required this.accountId,
    required this.assetCode,
    required this.assetName,
    required this.assetType,
    this.quantity = 0,
    this.costPrice = 0,
    this.currentPrice = 0,
    this.tags = const [],
    this.notes = '',
    this.currency = 'CNY',
    required this.createdAt,
    required this.updatedAt,
  });

  /// 市值
  double get marketValue => quantity * currentPrice;

  /// 成本
  double get totalCost => quantity * costPrice;

  /// 盈亏金额
  double get profitLoss => marketValue - totalCost;

  /// 盈亏比例
  double get profitLossPercent =>
      totalCost != 0 ? (profitLoss / totalCost) * 100 : 0;

  factory HoldingModel.fromJson(Map<String, dynamic> json) {
    List<String> parseTags(dynamic raw) {
      if (raw is List) return raw.cast<String>();
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.cast<String>();
      }
      return [];
    }

    return HoldingModel(
      id: json['id'] as String,
      accountId: json['accountId'] as String,
      assetCode: json['assetCode'] as String,
      assetName: json['assetName'] as String,
      assetType: AssetType.values.firstWhere(
        (e) => e.name == json['assetType'],
        orElse: () => AssetType.other,
      ),
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      costPrice: (json['costPrice'] as num?)?.toDouble() ?? 0,
      currentPrice: (json['currentPrice'] as num?)?.toDouble() ?? 0,
      tags: parseTags(json['tags']),
      notes: json['notes'] as String? ?? '',
      currency: json['currency'] as String? ?? 'CNY',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountId': accountId,
        'assetCode': assetCode,
        'assetName': assetName,
        'assetType': assetType.name,
        'quantity': quantity,
        'costPrice': costPrice,
        'currentPrice': currentPrice,
        'tags': tags,
        'notes': notes,
        'currency': currency,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  HoldingModel copyWith({
    String? id,
    String? accountId,
    String? assetCode,
    String? assetName,
    AssetType? assetType,
    double? quantity,
    double? costPrice,
    double? currentPrice,
    List<String>? tags,
    String? notes,
    String? currency,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return HoldingModel(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      assetCode: assetCode ?? this.assetCode,
      assetName: assetName ?? this.assetName,
      assetType: assetType ?? this.assetType,
      quantity: quantity ?? this.quantity,
      costPrice: costPrice ?? this.costPrice,
      currentPrice: currentPrice ?? this.currentPrice,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      currency: currency ?? this.currency,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
