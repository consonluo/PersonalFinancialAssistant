import 'package:dio/dio.dart';
import '../models/market_data_model.dart';
import 'market_api_client.dart';

/// 新浪财经 API - 美股行情
class SinaFinanceApi implements MarketApiClient {
  final Dio _dio;

  SinaFinanceApi({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'Referer': 'https://finance.sina.com.cn',
    },
  ));

  @override
  Future<List<MarketDataModel>> getQuotes(List<String> codes) async {
    final results = <MarketDataModel>[];
    for (final code in codes) {
      final result = await getQuote(code);
      if (result != null) results.add(result);
    }
    return results;
  }

  @override
  Future<MarketDataModel?> getQuote(String code) async {
    final symbol = _toSinaSymbol(code);
    if (symbol.isEmpty) return null;

    final url = 'https://hq.sinajs.cn/list=$symbol';
    final response = await _dio.get(url, options: Options(
      responseType: ResponseType.plain,
    ));

    if (response.statusCode != 200) return null;

    final text = response.data?.toString() ?? '';
    return _parseResponse(code, text);
  }

  String _toSinaSymbol(String code) {
    final upper = code.toUpperCase().trim();

    // 已有前缀
    if (upper.startsWith('GB_')) return upper.toLowerCase();

    // 纯字母代码（美股）
    if (RegExp(r'^[A-Z]{1,5}$').hasMatch(upper)) {
      return 'gb_\$${upper.toLowerCase()}';
    }

    // .US 后缀
    if (upper.endsWith('.US')) {
      final symbol = upper.replaceAll('.US', '');
      return 'gb_\$${symbol.toLowerCase()}';
    }

    return '';
  }

  MarketDataModel? _parseResponse(String code, String text) {
    // 新浪格式: var hq_str_gb_$aapl="苹果,195.20,...";
    final match = RegExp(r'"([^"]*)"').firstMatch(text);
    if (match == null) return null;

    final parts = match.group(1)?.split(',') ?? [];
    if (parts.length < 4) return null;

    final name = parts[0];
    final price = double.tryParse(parts[1]) ?? 0;
    final change = double.tryParse(parts[2]) ?? 0;
    final changePercent = double.tryParse(parts[3]) ?? 0;

    return MarketDataModel(
      assetCode: code.toUpperCase().replaceAll('.US', ''),
      name: name,
      price: price,
      change: change,
      changePercent: changePercent,
      updatedAt: DateTime.now(),
    );
  }
}
