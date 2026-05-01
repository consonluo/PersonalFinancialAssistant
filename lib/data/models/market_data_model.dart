/// 行情数据模型
class MarketDataModel {
  final String assetCode;
  final String name;
  final double price;
  final double change;
  final double changePercent;
  final double volume;
  final DateTime updatedAt;

  /// 行情币种（CNY/HKD/USD/EUR/GBP）。空字符串视为 CNY。
  /// 由各 API 按数据来源标注：东财 A 股=CNY、东财港股=HKD、新浪美股=USD、基金=CNY。
  final String currency;

  const MarketDataModel({
    required this.assetCode,
    this.name = '',
    this.price = 0,
    this.change = 0,
    this.changePercent = 0,
    this.volume = 0,
    required this.updatedAt,
    this.currency = 'CNY',
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
      currency: json['currency'] as String? ?? 'CNY',
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
        'currency': currency,
      };
}
