import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/market_data_model.dart';

/// 统一行情 API 接口
abstract class MarketApiClient {
  /// 批量获取行情数据
  Future<List<MarketDataModel>> getQuotes(List<String> codes);

  /// 获取单只行情
  Future<MarketDataModel?> getQuote(String code);
}

/// Web 端通过同源代理访问行情 API，避免 CORS 限制
class ApiProxy {
  ApiProxy._();

  static String get _origin {
    if (!kIsWeb) return '';
    final b = Uri.base;
    return '${b.scheme}://${b.host}${b.hasPort ? ':${b.port}' : ''}';
  }

  static String eastmoney(String path) =>
      kIsWeb ? '$_origin/api-proxy/eastmoney$path' : 'https://push2.eastmoney.com$path';

  static String sina(String path) =>
      kIsWeb ? '$_origin/api-proxy/sina$path' : 'https://hq.sinajs.cn$path';

  static String fundgz(String path) =>
      kIsWeb ? '$_origin/api-proxy/fundgz$path' : 'https://fundgz.1234567.com.cn$path';

  static String fundApi(String path) =>
      kIsWeb ? '$_origin/api-proxy/fundapi$path' : 'https://fundmobapi.eastmoney.com$path';
}
