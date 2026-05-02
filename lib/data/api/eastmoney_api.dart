import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/market_data_model.dart';
import 'market_api_client.dart';

/// 东方财富 API - A股/港股行情
class EastMoneyApi implements MarketApiClient {
  final Dio _dio;

  EastMoneyApi({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: const {
                'User-Agent':
                    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
                'Referer': 'https://quote.eastmoney.com/',
              },
            ),
          );

  @override
  Future<List<MarketDataModel>> getQuotes(List<String> codes) async {
    final results = <MarketDataModel>[];
    for (var i = 0; i < codes.length; i += 50) {
      final batch = codes.sublist(
        i,
        i + 50 > codes.length ? codes.length : i + 50,
      );
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

  /// 获取最近交易日收盘价（A/HK/US）
  Future<List<MarketDataModel>> getLastCloseQuotes(List<String> codes) async {
    final results = <MarketDataModel>[];
    for (final code in codes) {
      try {
        final one = await getLastCloseQuote(code);
        if (one != null && one.price > 0) results.add(one);
      } catch (e) {
        debugPrint('[EastMoneyApi] getLastCloseQuote($code) failed: $e');
      }
    }
    return results;
  }

  Future<MarketDataModel?> getLastCloseQuote(String code) async {
    final secIds = _closeSecIds(code);
    if (secIds.isEmpty) return null;

    for (final secId in secIds) {
      final marketId = int.tryParse(secId.split('.').first) ?? 0;
      final pureCode = secId.split('.').last;
      final quote = await _tryGetLastCloseBySecId(
        secId: secId,
        marketId: marketId,
        pureCode: pureCode,
      );
      if (quote != null) return quote;
    }
    return null;
  }

  Future<MarketDataModel?> _tryGetLastCloseBySecId({
    required String secId,
    required int marketId,
    required String pureCode,
  }) async {
    const hosts = <String>[
      'https://push2his.eastmoney.com',
      'https://push2.eastmoney.com',
    ];
    const query = <String, dynamic>{
      'klt': 101, // 日K
      'fqt': 0,
      'lmt': 5,
      'end': '20500000',
      'iscca': 1,
      // 东方财富常用 ut 参数，部分市场缺失会返回空 klines
      'ut': 'fa5fd1943c7b386f172d6893dbfba10b',
      'fields1': 'f1,f2,f3,f4,f5,f6,f7,f8',
      'fields2': 'f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61',
    };

    for (final host in hosts) {
      try {
        final response = await _dio.get(
          '$host/api/qt/stock/kline/get',
          queryParameters: {...query, 'secid': secId},
        );
        if (response.statusCode != 200) continue;
        final data = _asMap(response.data);
        final kdata = data?['data'];
        final klines = kdata?['klines'];
        if (klines is! List || klines.isEmpty) continue;

        final lastRaw = klines.last?.toString() ?? '';
        final last = lastRaw.split(',');
        // 约定: f51日期,f53收盘,f59涨跌幅,f60涨跌额
        if (last.length < 10) continue;

        final dateRaw = last[0].trim();
        final date =
            DateTime.tryParse(
              dateRaw.length >= 10 ? dateRaw.substring(0, 10) : dateRaw,
            ) ??
            _lastTradingDay();
        final close = double.tryParse(last[2]) ?? 0;
        final changePct = double.tryParse(last[8]) ?? 0;
        final change = double.tryParse(last[9]) ?? 0;

        if (close <= 0) continue;
        return MarketDataModel(
          assetCode: pureCode,
          name: kdata?['name']?.toString() ?? pureCode,
          price: close,
          change: change,
          changePercent: changePct,
          updatedAt: date,
          currency: _currencyForMarketId(marketId),
          source: MarketDataModel.sourceClose,
        );
      } catch (_) {
        // 继续尝试下一个 host / secid
      }
    }
    return null;
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
    final response = await _dio.get(
      url,
      queryParameters: {
        'fltt': 2,
        // f13 = 市场类型（0=深圳, 1=上海, 116=港股, 105=美股, 100=英股, 153=新加坡）
        'fields': 'f2,f3,f4,f5,f12,f13,f14,f86',
        'secids': secIds,
      },
    );

    if (response.statusCode != 200) return [];

    final data = _asMap(response.data);
    if (data == null || data['data'] == null || data['data']['diff'] == null) {
      return [];
    }

    final rawDiff = data['data']['diff'];
    final List<dynamic> items;
    if (rawDiff is List) {
      items = rawDiff;
    } else if (rawDiff is Map) {
      items = rawDiff.values.toList();
    } else {
      return [];
    }
    final results = <MarketDataModel>[];
    for (final item in items) {
      if (item is! Map) continue;
      final ts = (item['f86'] as num?)?.toInt();
      final updatedAt =
          ts != null && ts > 0
              ? DateTime.fromMillisecondsSinceEpoch(ts * 1000)
              : _lastTradingDay();
      // 根据市场代码 f13 推断币种
      final marketId = (item['f13'] as num?)?.toInt() ?? 0;
      final currency = _currencyForMarketId(marketId);
      final model = MarketDataModel(
        assetCode: item['f12']?.toString() ?? '',
        name: item['f14']?.toString() ?? '',
        price: (item['f2'] as num?)?.toDouble() ?? 0,
        changePercent: (item['f3'] as num?)?.toDouble() ?? 0,
        change: (item['f4'] as num?)?.toDouble() ?? 0,
        volume: (item['f5'] as num?)?.toDouble() ?? 0,
        updatedAt: updatedAt,
        currency: currency,
      );
      if (model.assetCode.isNotEmpty && model.price > 0) {
        results.add(model);
      }
    }
    return results;
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

  List<String> _closeSecIds(String code) {
    final secId = _toSecId(code);
    if (secId.isEmpty) return const [];

    final upperCode = code.toUpperCase().trim();
    final pureCode = upperCode.replaceAll(
      RegExp(r'\.(SH|SZ|HK|US|O|N)$', caseSensitive: false),
      '',
    );
    final market = secId.split('.').first;

    // 美股收盘价优先尝试 106(NYSE) + 105(NASDAQ)，并兼容 .N/.O 后缀映射。
    if (RegExp(r'^[A-Z]{1,5}$').hasMatch(pureCode) ||
        upperCode.endsWith('.US')) {
      final candidates = <String>{};
      final usCodes = <String>[pureCode, '$pureCode.N', '$pureCode.O'];
      for (final symbol in usCodes) {
        candidates.add('106.$symbol');
        candidates.add('105.$symbol');
      }
      return candidates.toList();
    }

    return <String>['$market.$pureCode'];
  }

  Map<String, dynamic>? _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    if (raw is! String) return null;

    final text = raw.trim();
    if (text.isEmpty) return null;

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {
      // 继续尝试从 callback 包裹中提取 JSON
    }

    final firstBrace = text.indexOf('{');
    final lastBrace = text.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      final jsonPart = text.substring(firstBrace, lastBrace + 1);
      try {
        final decoded = jsonDecode(jsonPart);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {}
    }
    return null;
  }
}
