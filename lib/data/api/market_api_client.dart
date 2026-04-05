import '../models/market_data_model.dart';

/// 统一行情 API 接口
abstract class MarketApiClient {
  /// 批量获取行情数据
  Future<List<MarketDataModel>> getQuotes(List<String> codes);

  /// 获取单只行情
  Future<MarketDataModel?> getQuote(String code);
}
