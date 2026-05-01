import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/market_data_model.dart';
import 'market_api_client.dart' show MarketApiClient, ApiProxy;

/// 新浪财经 API - 美股行情
class SinaFinanceApi implements MarketApiClient {
  final Dio _dio;

  SinaFinanceApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: {
                'Referer': 'https://finance.sina.com.cn',
              },
            ));

  @override
  Future<List<MarketDataModel>> getQuotes(List<String> codes) async {
    final results = <MarketDataModel>[];
    // 新浪支持 list=code1,code2 批量查询，减少请求次数提升稳定性
    final normalizedCodes =
        codes.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    for (var i = 0; i < normalizedCodes.length; i += 30) {
      final batch = normalizedCodes.sublist(
        i,
        i + 30 > normalizedCodes.length ? normalizedCodes.length : i + 30,
      );
      try {
        results.addAll(await _getQuotesBatch(batch));
      } catch (e) {
        debugPrint('[SinaApi] getQuotes batch failed: $e');
      }
    }
    return results;
  }

  @override
  Future<MarketDataModel?> getQuote(String code) async {
    final symbol = _toSinaSymbol(code, preferUs: true);
    if (symbol.isEmpty) return null;

    final url = ApiProxy.sina('/list=$symbol');
    final response = await _dio.get(url,
        options: Options(
          responseType: ResponseType.plain,
        ));

    if (response.statusCode != 200) return null;

    final text = response.data?.toString() ?? '';
    return _parseResponse(code.toUpperCase(), text);
  }

  Future<List<MarketDataModel>> _getQuotesBatch(List<String> codes) async {
    final mapping = <String, String>{};
    final symbols = <String>[];
    for (final code in codes) {
      final us = _toSinaSymbol(code, preferUs: true);
      if (us.isNotEmpty) {
        symbols.add(us);
        mapping[us] = code;
      }
    }
    if (symbols.isEmpty) return [];

    final url = ApiProxy.sina('/list=${symbols.join(',')}');
    final response = await _dio.get(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    if (response.statusCode != 200) return [];
    return _parseBatchResponse(response.data?.toString() ?? '', mapping);
  }

  String _toSinaSymbol(String code, {required bool preferUs}) {
    final upper = code.toUpperCase().trim();

    // 已有前缀
    if (upper.startsWith('GB_') || upper.startsWith('RT_HK')) {
      return upper.toLowerCase();
    }

    // 纯字母代码（美股）
    if (preferUs && RegExp(r'^[A-Z]{1,5}$').hasMatch(upper)) {
      return 'gb_\$${upper.toLowerCase()}';
    }

    // .US 后缀
    if (preferUs && upper.endsWith('.US')) {
      final symbol = upper.replaceAll('.US', '');
      return 'gb_\$${symbol.toLowerCase()}';
    }

    return '';
  }

  List<MarketDataModel> _parseBatchResponse(
    String text,
    Map<String, String> symbolToCode,
  ) {
    final results = <MarketDataModel>[];
    final lines = RegExp(r'var\s+hq_str_([^=]+)="([^"]*)";');
    for (final m in lines.allMatches(text)) {
      final rawSymbol = m.group(1)?.trim().toLowerCase() ?? '';
      final rawContent = m.group(2) ?? '';
      if (rawSymbol.isEmpty || rawContent.isEmpty) continue;
      final originalCode = symbolToCode[rawSymbol];
      if (originalCode == null) continue;
      final one = _parseContentToModel(originalCode.toUpperCase(), rawContent);
      if (one != null) results.add(one);
    }
    return results;
  }

  MarketDataModel? _parseResponse(String code, String text) {
    // 新浪格式: var hq_str_gb_$aapl="苹果,195.20,...";
    final match = RegExp(r'"([^"]*)"').firstMatch(text);
    if (match == null) return null;
    return _parseContentToModel(code, match.group(1) ?? '');
  }

  MarketDataModel? _parseContentToModel(String code, String content) {
    final parts = content.split(',');
    if (parts.length < 4) return null;
    final name = parts[0];
    final price = double.tryParse(parts[1]) ?? 0;
    final change = double.tryParse(parts[2]) ?? 0;
    final changePercent = double.tryParse(parts[3]) ?? 0;
    if (price <= 0) return null;
    return MarketDataModel(
      assetCode: code.toUpperCase().replaceAll('.US', ''),
      name: name,
      price: price,
      change: change,
      changePercent: changePercent,
      updatedAt: DateTime.now(),
      currency: 'USD',
    );
  }
}
