import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/market_data_model.dart';
import 'market_api_client.dart';

/// 东方财富 API - A股/港股行情
class EastMoneyApi implements MarketApiClient {
  final Dio _dio;

  EastMoneyApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ));

  @override
  Future<List<MarketDataModel>> getQuotes(List<String> codes) async {
    final results = <MarketDataModel>[];
    for (var i = 0; i < codes.length; i += 50) {
      final batch =
          codes.sublist(i, i + 50 > codes.length ? codes.length : i + 50);
      try {
        final batchResults = await _fetchBatchWithRetry(batch);
        results.addAll(batchResults);
      } catch (e) {
        debugPrint('[EastMoneyApi] fetchBatch failed: $e');
      }
    }
    return results;
  }

  @override
  Future<MarketDataModel?> getQuote(String code) async {
    final results = await getQuotes([code]);
    return results.isEmpty ? null : results.first;
  }

  Future<List<MarketDataModel>> _fetchBatchWithRetry(
    List<String> codes, {
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await _fetchBatch(codes);
      } catch (e) {
        lastError = e;
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
        }
      }
    }
    throw lastError ?? Exception('EastMoney batch failed');
  }

  Future<List<MarketDataModel>> _fetchBatch(List<String> codes) async {
    final secIds = codes.map(_toSecId).where((s) => s.isNotEmpty).join(',');
    if (secIds.isEmpty) return [];

    final url = ApiProxy.eastmoney('/api/qt/ulist.np/get');
    final response = await _dio.get(url, queryParameters: {
      'fltt': 2,
      // f13 = 市场类型（0=深圳, 1=上海, 116=港股, 105=美股, 100=英股, 153=新加坡）
      'fields': 'f2,f3,f4,f5,f12,f13,f14,f86',
      'secids': secIds,
    });

    if (response.statusCode != 200) return [];

    final data = response.data;
    if (data == null || data['data'] == null || data['data']['diff'] == null) {
      return [];
    }

    final List<dynamic> items = data['data']['diff'];
    return items.map((item) {
      final ts = (item['f86'] as num?)?.toInt();
      final updatedAt = ts != null && ts > 0
          ? DateTime.fromMillisecondsSinceEpoch(ts * 1000)
          : _lastTradingDay();
      // 根据市场代码 f13 推断币种
      final marketId = (item['f13'] as num?)?.toInt() ?? 0;
      final currency = _currencyForMarketId(marketId);
      return MarketDataModel(
        assetCode: item['f12']?.toString() ?? '',
        name: item['f14']?.toString() ?? '',
        price: (item['f2'] as num?)?.toDouble() ?? 0,
        changePercent: (item['f3'] as num?)?.toDouble() ?? 0,
        change: (item['f4'] as num?)?.toDouble() ?? 0,
        volume: (item['f5'] as num?)?.toDouble() ?? 0,
        updatedAt: updatedAt,
        currency: currency,
      );
    }).toList();
  }

  static String _currencyForMarketId(int marketId) {
    switch (marketId) {
      case 116:
        return 'HKD';
      case 105:
        return 'USD'; // NASDAQ
      case 106:
        return 'USD'; // NYSE
      case 100:
        return 'GBP'; // 英国
      case 153:
        return 'SGD'; // 新加坡
      default:
        return 'CNY'; // 0/1 = A股
    }
  }

  static DateTime _lastTradingDay() {
    var d = DateTime.now();
    if (d.hour < 9 || (d.hour == 9 && d.minute < 30)) {
      d = d.subtract(const Duration(days: 1));
    }
    while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      d = d.subtract(const Duration(days: 1));
    }
    return DateTime(d.year, d.month, d.day, 15, 0);
  }

  String _toSecId(String code) {
    final upperCode = code.toUpperCase().trim();
    final pureCode = upperCode.replaceAll(
      RegExp(r'\.(SH|SZ|HK|US)$', caseSensitive: false),
      '',
    );

    // A股 + 交易所ETF
    if (RegExp(r'^\d{6}$').hasMatch(pureCode)) {
      if (pureCode.startsWith('5') ||
          pureCode.startsWith('6') ||
          pureCode.startsWith('9')) {
        return '1.$pureCode'; // 上海（含51x/56x/58x ETF）
      }
      return '0.$pureCode'; // 深圳（含159xxx ETF）
    }

    // 港股
    if (upperCode.endsWith('.HK') || RegExp(r'^\d{1,5}$').hasMatch(pureCode)) {
      final hkCode = pureCode.padLeft(5, '0');
      return '116.$hkCode';
    }

    // 美股（纳斯达克默认市场）
    if (upperCode.endsWith('.US') ||
        RegExp(r'^[A-Z]{1,5}$').hasMatch(pureCode)) {
      return '105.$pureCode';
    }

    return '';
  }
}
