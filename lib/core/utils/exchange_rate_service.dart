import 'package:dio/dio.dart';

/// 汇率服务 - 查询实时汇率并转换金额
class ExchangeRateService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// 缓存汇率（同一次导入过程中复用）
  static final Map<String, double> _cache = {};
  static DateTime? _cacheTime;

  /// 币种符号映射
  static const currencySymbols = {
    'CNY': '¥',
    'HKD': 'HK\$',
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
  };

  /// 币种中文名
  static const currencyNames = {
    'CNY': '人民币',
    'HKD': '港币',
    'USD': '美元',
    'EUR': '欧元',
    'GBP': '英镑',
    'JPY': '日元',
  };

  /// 获取汇率（from -> CNY）
  /// 返回 1 单位 from 等于多少 CNY
  static Future<double> getRate(String from) async {
    if (from == 'CNY' || from.isEmpty) return 1.0;

    // 检查缓存（5分钟有效）
    final cacheKey = '${from}_CNY';
    if (_cacheTime != null &&
        DateTime.now().difference(_cacheTime!).inMinutes < 5 &&
        _cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    try {
      // 使用多个免费 API 作为 fallback
      final rate = await _fetchFromExchangeApi(from) ??
          await _fetchFromEcbProxy(from) ??
          _getFallbackRate(from);

      _cache[cacheKey] = rate;
      _cacheTime = DateTime.now();
      return rate;
    } catch (_) {
      return _getFallbackRate(from);
    }
  }

  /// 主 API: exchangerate-api.com (免费，无需key)
  static Future<double?> _fetchFromExchangeApi(String from) async {
    try {
      final url = 'https://open.er-api.com/v6/latest/$from';
      final response = await _dio.get(url);
      if (response.statusCode == 200 && response.data is Map) {
        final rates = response.data['rates'] as Map?;
        final cnyRate = rates?['CNY'];
        if (cnyRate is num && cnyRate > 0) return cnyRate.toDouble();
      }
    } catch (_) {}
    return null;
  }

  /// 备选 API
  static Future<double?> _fetchFromEcbProxy(String from) async {
    try {
      final url = 'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/${from.toLowerCase()}.json';
      final response = await _dio.get(url);
      if (response.statusCode == 200 && response.data is Map) {
        final rates = response.data[from.toLowerCase()] as Map?;
        final cnyRate = rates?['cny'];
        if (cnyRate is num && cnyRate > 0) return cnyRate.toDouble();
      }
    } catch (_) {}
    return null;
  }

  /// 离线兜底汇率（大致参考值）
  static double _getFallbackRate(String from) {
    const fallbackRates = {
      'USD': 7.25,
      'HKD': 0.93,
      'EUR': 7.90,
      'GBP': 9.20,
      'JPY': 0.048,
    };
    return fallbackRates[from] ?? 1.0;
  }

  /// 批量获取多种币种的汇率
  static Future<Map<String, double>> getRates(Set<String> currencies) async {
    final result = <String, double>{};
    for (final c in currencies) {
      result[c] = await getRate(c);
    }
    return result;
  }

  /// 转换金额
  static double convert(double amount, String from, {String to = 'CNY'}) {
    if (from == to) return amount;
    final rate = _cache['${from}_$to'] ?? _getFallbackRate(from);
    return amount * rate;
  }

  /// 清除缓存
  static void clearCache() {
    _cache.clear();
    _cacheTime = null;
  }
}
