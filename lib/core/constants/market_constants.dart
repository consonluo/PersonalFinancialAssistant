/// 市场相关常量
class MarketConstants {
  MarketConstants._();

  // ===== API 地址 =====
  /// 东方财富 A股/港股 行情
  static const String eastMoneyBaseUrl =
      'https://push2.eastmoney.com/api/qt/clist/get';

  /// 东方财富 单只股票行情
  static const String eastMoneyStockUrl =
      'https://push2his.eastmoney.com/api/qt/stock/get';

  /// 新浪财经美股行情
  static const String sinaUSStockUrl =
      'https://hq.sinajs.cn/list=';

  /// 天天基金 基金净值
  static const String fundBaseUrl =
      'https://fundgz.1702.top/api/v1/fund/detail';

  /// 天天基金 基金实时估值
  static const String fundEstimateUrl =
      'https://fundgz.1234567.com.cn/js/';

  // ===== 市场交易时间 =====
  /// A股交易时间 (UTC+8)
  static const int aStockOpenHour = 9;
  static const int aStockOpenMinute = 30;
  static const int aStockCloseHour = 15;
  static const int aStockCloseMinute = 0;

  /// 港股交易时间 (UTC+8)
  static const int hkStockOpenHour = 9;
  static const int hkStockOpenMinute = 30;
  static const int hkStockCloseHour = 16;
  static const int hkStockCloseMinute = 0;

  /// 美股交易时间 (UTC-4/EST, 北京时间 21:30 - 04:00)
  static const int usStockOpenHourCST = 21;
  static const int usStockOpenMinuteCST = 30;
  static const int usStockCloseHourCST = 4;
  static const int usStockCloseMinuteCST = 0;

  // ===== 代码前缀规则 =====
  /// A股代码前缀
  static const List<String> aStockPrefixes = [
    '60', // 上证主板
    '68', // 科创板
    '00', // 深证主板
    '30', // 创业板
  ];

  /// 港股代码特征
  static const String hkStockSuffix = '.HK';

  /// 美股交易所
  static const List<String> usExchanges = ['NASDAQ', 'NYSE', 'AMEX'];

  // ===== 分类关键词 =====
  static const Map<String, List<String>> classifyKeywords = {
    'bondFund': ['债券', '债基', '利率债', '信用债', '纯债', '短债'],
    'moneyFund': ['货币', '现金', '余额', '零钱'],
    'indexFund': [
      'ETF', 'etf', 'LOF', 'lof', '指数', '被动', '跟踪',
      '沪深300', '中证500', '中证1000', '上证50', '创业板指',
      '科创50', '国证', '恒生',
      '纳指', '纳斯达克', 'NASDAQ', 'QQQ', '标普', 'S&P',
    ],
    'activeFund': ['混合', '平衡', '灵活配置', '成长', '精选', '优选', '策略'],
  };
}
