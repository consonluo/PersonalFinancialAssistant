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
      final assetType = _getString(item, ['assetType', 'type', 'category']);
      final currency = _getString(item, ['currency', 'currencyCode', 'ccy']);

      if (code.isEmpty && name.isEmpty) continue;

      // ======== 原始提取 ========
      var qty = _getDouble(item, ['quantity', 'qty', 'shares', 'amount']);
      var unitCost = _getDouble(item, ['costPrice', 'cost', 'avgCost', 'buyPrice']);
      var unitPrice = _getDouble(item, ['currentPrice', 'price', 'lastPrice', 'latestPrice']);
      var totalCost = _getDouble(item, ['totalCost', 'totalCostPrice', 'investAmount', 'holdCost']);
      var totalMv = _getDouble(item, ['totalMarketValue', 'marketValue', 'value', 'totalValue']);
      var pnl = _getDouble(item, ['profitLoss', 'pnl', 'profit', 'gain', 'earnings']);
      var pnlPct = _getDouble(item, ['profitLossPercent', 'pnlPercent', 'returnRate', 'yieldRate', 'profitPercent']);

      final warnings = <String>[];

      // ======== 第一步：智能判断单价 vs 总价 ========
      // 如果 costPrice 比 totalCost 大，说明 AI 把总价填到了单价字段
      if (unitCost > 0 && totalCost > 0 && unitCost > totalCost * 0.9 && qty > 1) {
        // costPrice 其实是总成本
        final tmp = unitCost; unitCost = 0; totalCost = tmp;
      }
      if (unitPrice > 0 && totalMv > 0 && unitPrice > totalMv * 0.9 && qty > 1) {
        final tmp = unitPrice; unitPrice = 0; totalMv = tmp;
      }
      // 如果有数量且 costPrice 很大（远超单价合理范围），判断为总价
      if (qty > 1 && unitCost > 0 && totalCost <= 0) {
        if (_looksLikeTotalPrice(unitCost, qty, assetType)) {
          totalCost = unitCost; unitCost = 0;
        }
      }
      if (qty > 1 && unitPrice > 0 && totalMv <= 0) {
        if (_looksLikeTotalPrice(unitPrice, qty, assetType)) {
          totalMv = unitPrice; unitPrice = 0;
        }
      }

      // ======== 第二步：从已知值推算缺失值 ========
      // 总市值 ← 单价 × 数量
      if (totalMv <= 0 && unitPrice > 0 && qty > 0) totalMv = unitPrice * qty;
      // 总成本 ← 单价成本 × 数量
      if (totalCost <= 0 && unitCost > 0 && qty > 0) totalCost = unitCost * qty;
      // 单价 ← 总市值 / 数量
      if (unitPrice <= 0 && totalMv > 0 && qty > 0) unitPrice = totalMv / qty;
      // 单价成本 ← 总成本 / 数量
      if (unitCost <= 0 && totalCost > 0 && qty > 0) unitCost = totalCost / qty;
      // 数量 ← 总市值 / 单价
      if (qty <= 0 && unitPrice > 0 && totalMv > 0) qty = totalMv / unitPrice;
      // 总市值 ← 总成本 + 盈亏
      if (totalMv <= 0 && totalCost > 0 && pnl != 0) totalMv = totalCost + pnl;
      // 总成本 ← 总市值 - 盈亏
      if (totalCost <= 0 && totalMv > 0 && pnl != 0) totalCost = totalMv - pnl;

      // 从收益率推算成本
      if (unitCost <= 0 && unitPrice > 0 && pnlPct != 0) {
        unitCost = unitPrice / (1 + pnlPct / 100);
      }
      if (totalCost <= 0 && totalMv > 0 && pnlPct != 0) {
        totalCost = totalMv / (1 + pnlPct / 100);
      }

      // 盈亏额 ← 总市值 - 总成本
      if (pnl == 0 && totalMv > 0 && totalCost > 0) pnl = totalMv - totalCost;
      // 收益率 ← (总市值 - 总成本) / 总成本 × 100
      if (pnlPct == 0 && totalCost > 0 && totalMv > 0) pnlPct = (totalMv - totalCost) / totalCost * 100;

      // 再次补全单价和总价
      if (unitPrice <= 0 && totalMv > 0 && qty > 0) unitPrice = totalMv / qty;
      if (unitCost <= 0 && totalCost > 0 && qty > 0) unitCost = totalCost / qty;
      if (totalMv <= 0 && unitPrice > 0 && qty > 0) totalMv = unitPrice * qty;
      if (totalCost <= 0 && unitCost > 0 && qty > 0) totalCost = unitCost * qty;

      // ======== 第三步：存款/理财特殊处理 ========
      final isDepositLike = const {'deposit', 'wealth', 'moneyFund', 'fixedDeposit',
          'largeDeposit', 'noticeDeposit', 'structuredDeposit', 'insurance'}.contains(assetType);
      if (qty <= 0 && (totalMv > 0 || unitPrice > 0)) {
        if (isDepositLike) {
          qty = 1;
          if (totalMv > 0) { unitPrice = totalMv; }
          else { totalMv = unitPrice; }
          if (totalCost <= 0) { totalCost = totalMv; unitCost = unitPrice; }
        }
      }
      // 没有成本价就默认等于现价
      if (unitCost <= 0 && unitPrice > 0) unitCost = unitPrice;
      if (totalCost <= 0 && totalMv > 0) totalCost = totalMv;
      // 确保总市值有值
      if (totalMv <= 0 && unitPrice > 0 && qty > 0) totalMv = unitPrice * qty;

      // ======== 第四步：多维度交叉验证 ========

      // 验证1: 总市值 ≈ 单价 × 数量
      if (qty > 0 && unitPrice > 0 && totalMv > 0) {
        final computed = unitPrice * qty;
        final diff = (computed - totalMv).abs();
        if (diff > totalMv * 0.05 && diff > 1) { // 偏差超过5%
          // 信任总市值（截图直接显示），修正单价
          unitPrice = totalMv / qty;
          warnings.add('单价已按市值/数量修正');
        }
      }
      // 验证2: 总成本 ≈ 单价成本 × 数量
      if (qty > 0 && unitCost > 0 && totalCost > 0) {
        final computed = unitCost * qty;
        final diff = (computed - totalCost).abs();
        if (diff > totalCost * 0.05 && diff > 1) {
          unitCost = totalCost / qty;
        }
      }
      // 验证3: 盈亏额 ≈ 总市值 - 总成本
      if (totalMv > 0 && totalCost > 0 && pnl != 0) {
        final computedPnl = totalMv - totalCost;
        final diff = (computedPnl - pnl).abs();
        if (diff > totalMv * 0.05 && diff > 10) {
          warnings.add('盈亏与市值/成本不完全一致');
        }
      }
      // 验证4: 收益率 ≈ (总市值 - 总成本) / 总成本 × 100
      if (totalMv > 0 && totalCost > 0 && pnlPct != 0) {
        final computedPct = (totalMv - totalCost) / totalCost * 100;
        if ((computedPct - pnlPct).abs() > 2) { // 偏差超过2个百分点
          // 收益率更可信（截图直接标注的），用收益率反推成本
          totalCost = totalMv / (1 + pnlPct / 100);
          if (qty > 0) unitCost = totalCost / qty;
          warnings.add('成本已按收益率修正');
        }
      }

      // ======== 第五步：异常检测 ========
      if (unitCost > 0 && unitPrice > 0) {
        final calcPnl = (unitPrice - unitCost) / unitCost * 100;
        if (calcPnl > 500) warnings.add('盈利${calcPnl.toStringAsFixed(0)}%异常偏高');
        if (calcPnl < -90) warnings.add('亏损${calcPnl.abs().toStringAsFixed(0)}%异常偏高');
      }
      if (totalMv > 100000000) warnings.add('市值${(totalMv / 10000).toStringAsFixed(0)}万，请确认');
      if (qty < 0) { qty = qty.abs(); warnings.add('数量为负已修正'); }
      if (unitPrice < 0) { unitPrice = unitPrice.abs(); warnings.add('现价为负已修正'); }
      if (unitCost < 0) { unitCost = unitCost.abs(); warnings.add('成本价为负已修正'); }

      // ======== 推断币种 ========
      String resolvedCurrency = currency;
      if (resolvedCurrency.isEmpty) {
        resolvedCurrency = assetType == 'hkStock' ? 'HKD' : assetType == 'usStock' ? 'USD' : 'CNY';
      }

      results.add(ParsedHolding(
        code: code.isNotEmpty ? code : 'unknown',
        name: name.isNotEmpty ? name : code,
        quantity: qty,
        costPrice: unitCost,
        currentPrice: unitPrice,
        marketValue: totalMv,
        assetType: assetType.isNotEmpty ? assetType : '',
        currency: resolvedCurrency,
        warnings: warnings,
      ));
    }
    return results;
  }

  /// 判断一个价格是否像"总价"而非"单价"
  static bool _looksLikeTotalPrice(double price, double qty, String assetType) {
    if (qty <= 1) return false;
    // 基金类：净值通常在 0.5~10 之间，如果 price > 100 且有份额，大概率是总价
    final isFund = const {'indexETF', 'qdii', 'dividendFund', 'nasdaqETF',
        'bondFund', 'moneyFund', 'mixedFund'}.contains(assetType);
    if (isFund && price > 100 && qty > 10) return true;
    // 通用：如果 price / qty 的比值在合理单价范围内，则 price 是总价
    final unitGuess = price / qty;
    if (unitGuess > 0.1 && unitGuess < 10000 && price > 1000) return true;
    return false;
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
