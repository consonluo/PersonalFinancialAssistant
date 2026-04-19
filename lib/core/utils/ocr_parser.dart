import 'dart:convert';

/// OCR 解析器
/// 解析 AI 返回的 JSON 数据为结构化持仓列表
class OcrParser {
  OcrParser._();

  /// 解析 AI 返回的持仓数据
  static List<ParsedHolding> parseHoldingText(String text) {
    final jsonResult = _parseAsJson(text);
    if (jsonResult.isNotEmpty) return jsonResult;

    final markdownResult = _parseFromMarkdown(text);
    if (markdownResult.isNotEmpty) return markdownResult;

    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return _parseAsLegacyText(lines);
  }

  static List<ParsedHolding> _parseAsJson(String text) {
    try {
      final trimmed = text.trim();
      if (trimmed.startsWith('[')) {
        return _jsonListToHoldings(jsonDecode(trimmed) as List);
      }
      if (trimmed.startsWith('{')) {
        final obj = jsonDecode(trimmed) as Map<String, dynamic>;
        for (final key in ['holdings', 'data', 'result', 'results', 'positions', 'assets']) {
          if (obj[key] is List) return _jsonListToHoldings(obj[key] as List);
        }
      }
    } catch (_) {}
    return [];
  }

  static List<ParsedHolding> _parseFromMarkdown(String text) {
    final match = RegExp(r'```(?:json)?\s*\n?([\s\S]*?)\n?```').firstMatch(text);
    if (match != null) return _parseAsJson(match.group(1)?.trim() ?? '');
    return [];
  }

  static List<ParsedHolding> _jsonListToHoldings(List list) {
    final results = <ParsedHolding>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;

      final code = _getString(item, ['code', 'stockCode', 'assetCode', 'symbol']);
      final name = _getString(item, ['name', 'stockName', 'assetName']);
      var quantity = _getDouble(item, ['quantity', 'qty', 'shares', 'amount']);
      var costPrice = _getDouble(item, ['costPrice', 'cost', 'avgCost', 'buyPrice']);
      var currentPrice = _getDouble(item, ['currentPrice', 'price', 'lastPrice', 'latestPrice']);
      var marketValue = _getDouble(item, ['marketValue', 'value', 'totalValue']);
      final assetType = _getString(item, ['assetType', 'type', 'category']);
      final currency = _getString(item, ['currency', 'currencyCode', 'ccy']);
      // 额外字段用于推算
      final profitLoss = _getDouble(item, ['profitLoss', 'pnl', 'profit', 'gain', 'earnings']);
      final profitLossPercent = _getDouble(item, ['profitLossPercent', 'pnlPercent', 'returnRate', 'yieldRate', 'profitPercent']);

      if (code.isEmpty && name.isEmpty) continue;

      // ======== 智能推算缺失字段 ========
      
      // 1. 有现价和市值，推算数量
      if (quantity <= 0 && currentPrice > 0 && marketValue > 0) {
        quantity = marketValue / currentPrice;
      }
      // 2. 有数量和现价，推算市值
      if (marketValue <= 0 && quantity > 0 && currentPrice > 0) {
        marketValue = quantity * currentPrice;
      }
      // 3. 有数量和市值，推算现价
      if (currentPrice <= 0 && quantity > 0 && marketValue > 0) {
        currentPrice = marketValue / quantity;
      }
      // 4. 有现价和收益率，推算成本价：costPrice = currentPrice / (1 + rate/100)
      if (costPrice <= 0 && currentPrice > 0 && profitLossPercent != 0) {
        costPrice = currentPrice / (1 + profitLossPercent / 100);
      }
      // 5. 有现价和收益额+数量，推算成本价：costPrice = currentPrice - profitLoss/quantity
      if (costPrice <= 0 && currentPrice > 0 && profitLoss != 0 && quantity > 0) {
        costPrice = currentPrice - profitLoss / quantity;
      }
      // 6. 有市值和收益额，推算成本总额 → 再推成本价
      if (costPrice <= 0 && marketValue > 0 && profitLoss != 0 && quantity > 0) {
        final totalCost = marketValue - profitLoss;
        if (totalCost > 0) costPrice = totalCost / quantity;
      }
      // 7. 没有成本价但有现价，成本价默认等于现价
      if (costPrice <= 0 && currentPrice > 0) {
        costPrice = currentPrice;
      }
      // 8. 存款/理财类：如果 quantity=0 但有市值，设 quantity=1
      if (quantity <= 0 && marketValue > 0) {
        final isDepositOrWealth = const {'deposit', 'wealth', 'moneyFund', 'fixedDeposit', 'largeDeposit', 'noticeDeposit', 'structuredDeposit'}.contains(assetType);
        if (isDepositOrWealth || currentPrice <= 0) {
          quantity = 1;
          currentPrice = marketValue;
          if (costPrice <= 0) costPrice = marketValue;
        }
      }
      // 9. 确保 marketValue 有值
      if (marketValue <= 0 && quantity > 0 && currentPrice > 0) {
        marketValue = quantity * currentPrice;
      }

      // ======== 数据合理性校验 ========
      final warnings = <String>[];
      
      // 盈亏异常（超过200%或亏损超过90%）
      if (costPrice > 0 && currentPrice > 0) {
        final pnlPct = (currentPrice - costPrice) / costPrice * 100;
        if (pnlPct > 200) warnings.add('盈利${pnlPct.toStringAsFixed(0)}%偏高');
        if (pnlPct < -90) warnings.add('亏损${pnlPct.abs().toStringAsFixed(0)}%偏高');
      }
      // 市值异常（单只超过1亿）
      if (marketValue > 100000000) {
        warnings.add('市值${(marketValue / 10000).toStringAsFixed(0)}万，请确认');
      }
      // 数量异常（负数）
      if (quantity < 0) {
        warnings.add('数量为负');
        quantity = quantity.abs();
      }
      // 价格异常（负数）
      if (currentPrice < 0) { currentPrice = currentPrice.abs(); warnings.add('现价为负已修正'); }
      if (costPrice < 0) { costPrice = costPrice.abs(); warnings.add('成本价为负已修正'); }

      // 根据 assetType 推断币种
      String resolvedCurrency = currency;
      if (resolvedCurrency.isEmpty) {
        if (assetType == 'hkStock') {
          resolvedCurrency = 'HKD';
        } else if (assetType == 'usStock') {
          resolvedCurrency = 'USD';
        } else {
          resolvedCurrency = 'CNY';
        }
      }

      results.add(ParsedHolding(
        code: code.isNotEmpty ? code : 'unknown',
        name: name.isNotEmpty ? name : code,
        quantity: quantity,
        costPrice: costPrice,
        currentPrice: currentPrice,
        marketValue: marketValue,
        assetType: assetType.isNotEmpty ? assetType : '',
        currency: resolvedCurrency,
        warnings: warnings,
      ));
    }
    return results;
  }

  static String _getString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null && value.toString().trim().isNotEmpty) return value.toString().trim();
    }
    return '';
  }

  static double _getDouble(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        final cleaned = value.replaceAll(',', '').replaceAll('¥', '').replaceAll('￥', '').trim();
        final parsed = double.tryParse(cleaned);
        if (parsed != null) return parsed;
      }
    }
    return 0;
  }

  static List<ParsedHolding> _parseAsLegacyText(List<String> lines) {
    final results = <ParsedHolding>[];
    final headerKeywords = RegExp(r'(名称|代码|持仓|数量|成本|现价|市值|盈亏|涨跌)');
    for (final line in lines) {
      if (_isHeaderLine(line, headerKeywords)) continue;
      if (line.trim().length < 8) continue;
      final codeMatch = RegExp(r'(?<!\.)(\d{6})(?!\d)').firstMatch(line);
      if (codeMatch == null) continue;
      final code = codeMatch.group(1)!;
      final nameMatches = RegExp(r'([\u4e00-\u9fa5]{2,}[A-Za-z\u4e00-\u9fa5]*)').allMatches(line).toList();
      String name = code;
      for (final m in nameMatches) {
        final candidate = m.group(1) ?? '';
        if (!headerKeywords.hasMatch(candidate) && candidate.length >= 2) { name = candidate; break; }
      }
      final cleanLine = line.replaceFirst(code, ' ');
      final numbers = RegExp(r'-?\d[\d,]*\.?\d*')
          .allMatches(cleanLine).map((m) => m.group(0)!.replaceAll(',', ''))
          .map((s) => double.tryParse(s)).where((n) => n != null).map((n) => n!).toList();
      if (numbers.length >= 3) {
        results.add(ParsedHolding(
          code: code, name: name, quantity: numbers[0], costPrice: numbers[1],
          currentPrice: numbers[2], marketValue: numbers.length >= 4 ? numbers[3] : numbers[0] * numbers[2],
        ));
      }
    }
    return results;
  }

  static bool _isHeaderLine(String line, RegExp keywords) {
    int count = 0;
    for (final kw in ['名称', '代码', '数量', '成本', '现价', '市值', '盈亏']) {
      if (line.contains(kw)) count++;
    }
    return count >= 2;
  }
}

/// 解析出的持仓数据
class ParsedHolding {
  final String code;
  final String name;
  final double quantity;
  final double costPrice;
  final double currentPrice;
  final double marketValue;
  final String assetType; // AI 识别的资产类型
  final String currency; // 币种: CNY/HKD/USD/EUR/GBP/JPY
  final List<String> warnings; // 数据异常警告

  const ParsedHolding({
    required this.code,
    required this.name,
    required this.quantity,
    required this.costPrice,
    required this.currentPrice,
    required this.marketValue,
    this.assetType = '',
    this.currency = 'CNY',
    this.warnings = const [],
  });

  ParsedHolding copyWith({
    String? code, String? name, double? quantity, double? costPrice,
    double? currentPrice, double? marketValue, String? assetType, String? currency,
    List<String>? warnings,
  }) {
    return ParsedHolding(
      code: code ?? this.code, name: name ?? this.name,
      quantity: quantity ?? this.quantity, costPrice: costPrice ?? this.costPrice,
      currentPrice: currentPrice ?? this.currentPrice, marketValue: marketValue ?? this.marketValue,
      assetType: assetType ?? this.assetType, currency: currency ?? this.currency,
      warnings: warnings ?? this.warnings,
    );
  }

  /// 是否需要汇率转换
  bool get needsCurrencyConversion => currency != 'CNY' && currency.isNotEmpty;

  /// 是否有异常警告
  bool get hasWarnings => warnings.isNotEmpty;

  @override
  String toString() => 'ParsedHolding($code, $name, type=$assetType, currency=$currency, mv=$marketValue${warnings.isNotEmpty ? ", warn=${warnings.join(";")}" : ""})';
}
