/// 行情数据模型
class MarketDataModel {
  final String assetCode;
  final String name;
  final double price;
  final double change;
  final double changePercent;
  final double volume;
  final DateTime updatedAt;

  const MarketDataModel({
    required this.assetCode,
    this.name = '',
    this.price = 0,
    this.change = 0,
    this.changePercent = 0,
    this.volume = 0,
    required this.updatedAt,
  });

  bool get isUp => change > 0;
  bool get isDown => change < 0;
  bool get isFlat => change == 0;

  factory MarketDataModel.fromJson(Map<String, dynamic> json) {
    return MarketDataModel(
      assetCode: json['assetCode'] as String,
      name: json['name'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      change: (json['change'] as num?)?.toDouble() ?? 0,
      changePercent: (json['changePercent'] as num?)?.toDouble() ?? 0,
      volume: (json['volume'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'assetCode': assetCode,
        'name': name,
        'price': price,
        'change': change,
        'changePercent': changePercent,
        'volume': volume,
        'updatedAt': updatedAt.toIso8601String(),
      };
}
