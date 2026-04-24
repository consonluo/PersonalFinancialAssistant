import 'package:dio/dio.dart';
import '../models/market_data_model.dart';
import 'market_api_client.dart';

/// 天天基金 API - 基金净值查询
class FundApi implements MarketApiClient {
  final Dio _dio;

  FundApi({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'Referer': 'https://fund.eastmoney.com',
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
    final pureCode = code.replaceAll(RegExp(r'\.(OF|SZ|SH)$', caseSensitive: false), '');
    if (!RegExp(r'^\d{6}$').hasMatch(pureCode)) return null;

    // 使用天天基金实时估值接口
    final url = 'https://fundgz.1234567.com.cn/js/$pureCode.js';
    final response = await _dio.get(url, options: Options(
      responseType: ResponseType.plain,
    ));

    if (response.statusCode != 200) return null;

    final text = response.data?.toString() ?? '';
    return _parseResponse(pureCode, text);
  }

  MarketDataModel? _parseResponse(String code, String text) {
    // 格式: jsonpgz({"fundcode":"000001","name":"xxx","jzrq":"2024-01-01",
    //        "dwjz":"1.0","gsz":"1.01","gszzl":"1.00%",...});
    final match = RegExp(r'\{[^}]+\}').firstMatch(text);
    if (match == null) return null;

    final jsonStr = match.group(0)!;
    final fields = <String, String>{};

    for (final fieldMatch in RegExp(r'"(\w+)":"([^"]*)"').allMatches(jsonStr)) {
      fields[fieldMatch.group(1)!] = fieldMatch.group(2)!;
    }

    final name = fields['name'] ?? code;
    final dwjz = double.tryParse(fields['dwjz'] ?? '') ?? 0; // 昨日/最新公布净值
    final gszRaw = double.tryParse(fields['gsz'] ?? '') ?? 0; // 估算净值（盘中才有）
    final gszzl = double.tryParse(
        (fields['gszzl'] ?? '0').replaceAll('%', '')) ?? 0; // 估算涨幅%

    final hasEstimate = gszRaw > 0 && gszzl != 0;
    final price = hasEstimate ? gszRaw : dwjz;
    final change = hasEstimate ? gszRaw - dwjz : 0.0;
    final changePercent = hasEstimate ? gszzl : 0.0;

    if (price <= 0) return null;

    return MarketDataModel(
      assetCode: code,
      name: name,
      price: price,
      change: change,
      changePercent: changePercent,
      updatedAt: DateTime.now(),
    );
  }
}
