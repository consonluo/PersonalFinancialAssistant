import '../constants/app_constants.dart';
import '../constants/market_constants.dart';

/// 资产自动分类引擎
/// 基于持仓代码前缀和名称关键词进行规则匹配
class AssetClassifier {
  AssetClassifier._();

  /// 根据代码和名称自动分类
  static AssetType classify(String code, String name) {
    final upperCode = code.toUpperCase().trim();
    final upperName = name.toUpperCase().trim();

    // 1. 先按名称关键词匹配基金类型
    final fundType = _classifyByName(name);
    if (fundType != null) return fundType;

    // 2. 按代码前缀匹配市场
    final marketType = _classifyByCode(upperCode);
    if (marketType != null) return marketType;

    // 3. 检查是否为基金代码（6位纯数字，但不是A股格式）
    if (_isFundCode(upperCode)) {
      return _classifyFundByName(name);
    }

    // 4. 检查名称中是否含有 ETF
    if (upperName.contains('ETF')) return AssetType.indexETF;

    return AssetType.other;
  }

  /// 按名称关键词分类
  static AssetType? _classifyByName(String name) {
    final lowerName = name.toLowerCase();

    // 货币基金
    for (final kw in MarketConstants.classifyKeywords['moneyFund']!) {
      if (lowerName.contains(kw.toLowerCase())) return AssetType.moneyFund;
    }

    // 债券基金
    for (final kw in MarketConstants.classifyKeywords['bondFund']!) {
      if (lowerName.contains(kw.toLowerCase())) return AssetType.bondFund;
    }

    // 红利基金
    for (final kw in MarketConstants.classifyKeywords['dividendFund']!) {
      if (lowerName.contains(kw.toLowerCase())) return AssetType.dividendFund;
    }

    // 纳指ETF
    for (final kw in MarketConstants.classifyKeywords['nasdaqETF']!) {
      if (lowerName.contains(kw.toLowerCase())) return AssetType.nasdaqETF;
    }

    // QDII
    for (final kw in MarketConstants.classifyKeywords['qdii']!) {
      if (lowerName.contains(kw.toLowerCase())) return AssetType.qdii;
    }

    // 指数ETF
    for (final kw in MarketConstants.classifyKeywords['indexETF']!) {
      if (lowerName.contains(kw.toLowerCase())) return AssetType.indexETF;
    }

    // 混合基金
    for (final kw in MarketConstants.classifyKeywords['mixedFund']!) {
      if (lowerName.contains(kw.toLowerCase())) return AssetType.mixedFund;
    }

    return null;
  }

  /// 按代码前缀分类市场
  static AssetType? _classifyByCode(String code) {
    // 港股
    if (code.endsWith('.HK') || code.endsWith('.HKEX')) {
      return AssetType.hkStock;
    }

    // 美股（通常是字母代码）
    if (RegExp(r'^[A-Z]{1,5}$').hasMatch(code) ||
        code.endsWith('.US') ||
        code.endsWith('.O') || // NASDAQ
        code.endsWith('.N')) { // NYSE
      return AssetType.usStock;
    }

    // A股
    if (code.length == 6 && RegExp(r'^\d{6}$').hasMatch(code)) {
      for (final prefix in MarketConstants.aStockPrefixes) {
        if (code.startsWith(prefix)) return AssetType.aStock;
      }
    }

    // A股带后缀
    if (code.endsWith('.SH') || code.endsWith('.SZ')) {
      return AssetType.aStock;
    }

    return null;
  }

  /// 判断是否为基金代码
  static bool _isFundCode(String code) {
    // 基金代码通常为6位数字
    final pureCode = code.replaceAll(RegExp(r'\.(OF|SZ|SH)$'), '');
    return pureCode.length == 6 && RegExp(r'^\d{6}$').hasMatch(pureCode);
  }

  /// 根据名称细分基金类型
  static AssetType _classifyFundByName(String name) {
    final type = _classifyByName(name);
    if (type != null) return type;
    return AssetType.mixedFund; // 默认为混合基金
  }

  /// 批量分类
  static Map<String, AssetType> classifyBatch(
      Map<String, String> codeNameMap) {
    return codeNameMap.map(
        (code, name) => MapEntry(code, classify(code, name)));
  }

  /// 获取分类显示名称
  static String getCategoryDisplayName(AssetType type) {
    return type.label;
  }

  /// 获取大类分组（用于汇总分析）
  static String getMajorCategory(AssetType type) {
    switch (type) {
      case AssetType.aStock:
      case AssetType.hkStock:
      case AssetType.usStock:
        return '股票';
      case AssetType.indexETF:
      case AssetType.nasdaqETF:
        return 'ETF';
      case AssetType.qdii:
      case AssetType.dividendFund:
      case AssetType.bondFund:
      case AssetType.moneyFund:
      case AssetType.mixedFund:
        return '基金';
      case AssetType.wealth:
      case AssetType.deposit:
        return '现金类';
      case AssetType.realEstate:
      case AssetType.vehicle:
        return '固定资产';
      case AssetType.other:
        return '其他';
    }
  }
}
