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
        return _jsonListToHoldings(jsonDecode(trimmed) as List, text);
      }
      if (trimmed.startsWith('{')) {
        final obj = jsonDecode(trimmed) as Map<String, dynamic>;
        for (final key in ['holdings', 'data', 'result', 'results', 'positions', 'assets']) {
          if (obj[key] is List) return _jsonListToHoldings(obj[key] as List, text);
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

  static List<ParsedHolding> _jsonListToHoldings(List list, String originalText) {
    final results = <ParsedHolding>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;

      final code = _getString(item, ['code', 'stockCode', 'assetCode', 'symbol']);
      final name = _getString(item, ['name', 'stockName', 'assetName']);
      final assetType = _getString(item, ['assetType', 'type', 'category']);
      final currency = _getString(item, ['currency', 'currencyCode', 'ccy']);
      // AI 聚合标签（多标签）
      final aiTags = _getStringList(item, ['tags', 'aiTags', 'aggregations', 'groupings']);

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
      
      // ======== 提取原始文本中的货币符号和名称关键词 ========
      final itemText = item.toString();
      final combinedText = '$originalText $itemText';
      final upperText = combinedText.toUpperCase();
      final hasDollarSign = upperText.contains('\$') || upperText.contains('USD') || combinedText.contains('美元');
      final hasYenSign = combinedText.contains('¥') || combinedText.contains('￥') || upperText.contains('CNY') || combinedText.contains('人民币');
      final hasHkdSign = upperText.contains('HK\$') || upperText.contains('HKD') || combinedText.contains('港元') || combinedText.contains('港币');
      final hasGBP = upperText.contains('GBP') || combinedText.contains('英镑');
      final hasEUR = upperText.contains('EUR') || combinedText.contains('欧元');

      // ======== 第一步：智能判断单价 vs 总价 ========
      // 核心原则：总值最可靠，优先信任总值，其他字段由总值反推
      
      // 如果 costPrice 比 totalCost 大，说明 AI 把总价填到了单价字段
      if (unitCost > 0 && totalCost > 0 && unitCost > totalCost * 0.9 && qty > 1) {
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

      // ======== 第二步：总值优先原则补全缺失字段 ========
      // 总值是最可靠的，优先保证总值正确
      // 如果没有总值但有单价和数量，尝试计算
      if (totalMv <= 0 && unitPrice > 0 && qty > 0) {
        totalMv = unitPrice * qty;
      }
      if (totalCost <= 0 && unitCost != 0 && qty > 0) {
        // 注意：成本允许为负数（如做空、涡轮等）
        totalCost = unitCost * qty;
      }
      
      // 从总值反推单价
      if (unitPrice <= 0 && totalMv > 0 && qty > 0) {
        unitPrice = totalMv / qty;
      }
      // 从总值反推成本单价（成本允许负数）
      if (unitCost == 0 && totalCost != 0 && qty > 0) {
        unitCost = totalCost / qty;
      }
      // 从总值和盈亏反推成本
      if (totalCost <= 0 && totalMv > 0 && pnl != 0) {
        totalCost = totalMv - pnl;
        if (qty > 0) unitCost = totalCost / qty;
      }
      // 从收益率反推成本
      if (totalCost <= 0 && totalMv > 0 && pnlPct != 0) {
        totalCost = totalMv / (1 + pnlPct / 100);
        if (qty > 0) unitCost = totalCost / qty;
      }
      // 从盈亏和成本反推市值
      if (totalMv <= 0 && totalCost != 0 && pnl != 0) {
        totalMv = totalCost + pnl;
      }
      // 从盈亏和市值反推成本
      if (totalCost == 0 && totalMv > 0 && pnl != 0) {
        totalCost = totalMv - pnl;
        if (qty > 0) unitCost = totalCost / qty;
      }
      // 从盈亏百分比和市值反推成本
      if (totalCost == 0 && totalMv > 0 && pnlPct != 0) {
        totalCost = totalMv / (1 + pnlPct / 100);
        if (qty > 0) unitCost = totalCost / qty;
      }
      // 从盈亏百分比和成本反推市值
      if (totalMv <= 0 && totalCost != 0 && pnlPct != 0) {
        totalMv = totalCost * (1 + pnlPct / 100);
      }

      // 盈亏额 ← 总市值 - 总成本
      if (pnl == 0 && totalMv > 0 && totalCost != 0) pnl = totalMv - totalCost;
      // 收益率 ← (总市值 - 总成本) / 总成本 × 100
      if (pnlPct == 0 && totalCost != 0 && totalMv > 0) pnlPct = (totalMv - totalCost) / totalCost * 100;

      // 确保数量有值（存款/理财等数量为1）
      if (qty <= 0 && (totalMv > 0 || unitPrice > 0)) {
        final isDepositLike = const {'deposit', 'wealth', 'moneyFund', 'fixedDeposit',
            'largeDeposit', 'noticeDeposit', 'structuredDeposit', 'insurance'}.contains(assetType);
        if (isDepositLike) {
          qty = 1;
        } else if (unitPrice > 0 && totalMv > 0) {
          qty = totalMv / unitPrice;
        }
      }

      // ======== 第三步：存款/理财特殊处理 ========
      final isDepositLike = const {'deposit', 'wealth', 'moneyFund', 'fixedDeposit',
          'largeDeposit', 'noticeDeposit', 'structuredDeposit', 'insurance'}.contains(assetType);
      if (qty <= 0 && (totalMv > 0 || unitPrice > 0)) {
        if (isDepositLike) {
          qty = 1;
          if (totalMv > 0) { unitPrice = totalMv; }
          else { totalMv = unitPrice; }
          if (totalCost == 0) { totalCost = totalMv; unitCost = unitPrice; }
        }
      }
      // 没有成本价就默认等于现价（存款理财等）
      if (isDepositLike && unitCost == 0 && unitPrice > 0) {
        unitCost = unitPrice;
      }
      if (isDepositLike && totalCost == 0 && totalMv > 0) {
        totalCost = totalMv;
      }

      // ======== 第四步：交叉验证（信任总值） ========
      // 总值是截图直接显示的，最可靠
      if (qty > 0 && totalMv > 0 && unitPrice > 0) {
        final computed = unitPrice * qty;
        final diff = (computed - totalMv).abs();
        if (diff > totalMv * 0.05 && diff > 1) {
          unitPrice = totalMv / qty;
          warnings.add('单价已按市值修正');
        }
      }
      // 成本验证（成本允许负数）
      if (qty > 0 && totalCost != 0 && unitCost != 0) {
        final computed = unitCost * qty;
        final diff = (computed - totalCost).abs();
        if (totalCost != 0 && diff > totalCost.abs() * 0.05 && diff > 1) {
          unitCost = totalCost / qty;
        }
      }
      // 收益率验证
      if (totalMv > 0 && totalCost != 0 && pnlPct != 0) {
        final computedPct = (totalMv - totalCost) / totalCost * 100;
        if ((computedPct - pnlPct).abs() > 2) {
          // 收益率更可信，用收益率反推成本
          totalCost = totalMv / (1 + pnlPct / 100);
          if (qty > 0) unitCost = totalCost / qty;
          warnings.add('成本已按收益率修正');
        }
      }

      // ======== 第五步：合理性判断 ========
      if (qty > 0 && totalMv > 0) {
        final isStock = const {'aStock', 'hkStock', 'usStock'}.contains(assetType);
        final isFund = const {'indexFund', 'activeFund', 'bondFund', 'moneyFund'}.contains(assetType);
        
        if (isStock && unitPrice > 0) {
          // A股股价异常检测
          if (code.length == 6 && unitPrice > 1000) {
            warnings.add('A 股单价偏高，请确认');
          }
        }
        if (isFund && unitPrice > 0) {
          if (unitPrice > 20) warnings.add('基金净值偏高，请确认');
        }
        if (totalMv > 100000000) warnings.add('市值较大，请确认');
      }

      // ======== 第六步：异常检测 ========
      if (unitPrice > 0 && unitCost != 0) {
        final calcPnl = (unitPrice - unitCost) / unitCost * 100;
        if (calcPnl > 500) warnings.add('盈利异常偏高');
        if (calcPnl < -90) warnings.add('亏损异常偏高');
      }
      if (totalMv > 100000000) warnings.add('市值较大，请确认');
      if (qty < 0) { qty = qty.abs(); warnings.add('数量为负已修正'); }
      if (unitPrice < 0) { unitPrice = unitPrice.abs(); warnings.add('现价为负已修正'); }
      // 注意：成本允许负数，不再自动修正

      // ======== 推断币种（代码优先级最高） ========
      String resolvedCurrency = currency;
      
      // 第一优先级：直接根据代码判断（最准确）
      final codeCurrency = _detectCurrencyByCode(code);
      if (codeCurrency.isNotEmpty) {
        resolvedCurrency = codeCurrency;
      }
      
      // 第二优先级：AI 识别
      if (resolvedCurrency.isEmpty && currency.isNotEmpty) {
        resolvedCurrency = currency;
      }
      
      // 第三优先级：名称关键词（纳斯达克、港交所等）
      if (resolvedCurrency.isEmpty) {
        final nameUpper = name.toUpperCase();
        if (nameUpper.contains('NASDAQ') || nameUpper.contains('纽交所') || 
            nameUpper.contains('纳斯达克') || upperText.contains('美国')) {
          resolvedCurrency = 'USD';
        } else if (nameUpper.contains('港交所') || nameUpper.contains('港股')) {
          resolvedCurrency = 'HKD';
        }
      }
      
      // 第四优先级：资产类型
      if (resolvedCurrency.isEmpty) {
        if (const {'usStock'}.contains(assetType)) {
          resolvedCurrency = 'USD';
        } else if (const {'hkStock'}.contains(assetType)) {
          resolvedCurrency = 'HKD';
        } else if (const {
          'aStock', 'indexFund', 'activeFund', 'bondFund', 'moneyFund',
          'deposit', 'wealth', 'fixedDeposit', 'largeDeposit', 'noticeDeposit',
          'structuredDeposit', 'treasuryRepo', 'realEstate', 'vehicle',
        }.contains(assetType)) {
          resolvedCurrency = 'CNY';
        }
      }
      
      // 第五优先级：货币符号（谨慎使用，容易误判）
      if (resolvedCurrency.isEmpty) {
        if (hasDollarSign && !hasYenSign && !hasHkdSign) {
          resolvedCurrency = 'USD';
        } else if (hasHkdSign) {
          resolvedCurrency = 'HKD';
        } else if (hasGBP) {
          resolvedCurrency = 'GBP';
        } else if (hasEUR) {
          resolvedCurrency = 'EUR';
        }
      }
      
      // 默认人民币
      if (resolvedCurrency.isEmpty) {
        resolvedCurrency = 'CNY';
      }
      
      // 统一币种格式
      resolvedCurrency = resolvedCurrency.toUpperCase();
      if (resolvedCurrency == 'RMB' || resolvedCurrency == 'YEN') resolvedCurrency = 'CNY';
      if (resolvedCurrency == 'DOLLAR' || resolvedCurrency == 'DOLLARS') resolvedCurrency = 'USD';

      // ======== 推断 AI 聚合标签 ========
      // 如果 AI 返回了标签，直接使用
      var resolvedTags = aiTags;
      
      // 如果没有标签，根据名称和代码智能推断
      if (resolvedTags.isEmpty) {
        resolvedTags = _inferTags(code, name, assetType);
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
        aiTags: resolvedTags,
        warnings: warnings,
      ));
    }
    return results;
  }

  /// 根据股票代码和名称推断聚合标签
  static List<String> _inferTags(String code, String name, String assetType) {
    final tags = <String>[];
    final nameUpper = name.toUpperCase();
    final codeUpper = code.toUpperCase();
    
    // 指数标签
    if (nameUpper.contains('纳斯达克') || nameUpper.contains('NASDAQ') || 
        nameUpper.contains('纳指') || codeUpper == 'NDX' || codeUpper == 'QQQ') {
      tags.add('纳指');
    }
    if (nameUpper.contains('标普') || nameUpper.contains('S&P') || 
        codeUpper == 'SPY' || codeUpper == 'VOO') {
      tags.add('标普500');
    }
    if (nameUpper.contains('道琼斯') || codeUpper == 'DIA') {
      tags.add('道琼斯');
    }
    if (nameUpper.contains('沪深300') || nameUpper.contains('300') || codeUpper == '510300') {
      tags.add('沪深300');
    }
    if (nameUpper.contains('上证') || (code.length == 6 && code.startsWith('6'))) {
      tags.add('上证');
    }
    if (nameUpper.contains('创业板') || (code.length == 6 && code.startsWith('3'))) {
      tags.add('创业板');
    }
    if (nameUpper.contains('恒生') || nameUpper.contains('H股') || 
        (code.length == 5 && RegExp(r'^[0689]\d{4}$').hasMatch(code))) {
      tags.add('港股');
    }
    
    // 红利/高股息标签
    if (nameUpper.contains('红利') || nameUpper.contains('高股息') || 
        nameUpper.contains('股息') || nameUpper.contains('分红')) {
      tags.add('红利');
    }
    
    // 行业/主题标签
    if (nameUpper.contains('消费')) tags.add('消费');
    if (nameUpper.contains('科技')) tags.add('科技');
    if (nameUpper.contains('医药') || nameUpper.contains('医疗')) tags.add('医药');
    if (nameUpper.contains('新能源') || nameUpper.contains('光伏')) tags.add('新能源');
    if (nameUpper.contains('半导体') || nameUpper.contains('芯片')) tags.add('半导体');
    if (nameUpper.contains('军工') || nameUpper.contains('国防')) tags.add('军工');
    if (nameUpper.contains('金融') || nameUpper.contains('银行')) tags.add('金融');
    if (nameUpper.contains('白酒')) tags.add('白酒');
    if (nameUpper.contains('互联网')) tags.add('互联网');
    
    // 市场标签
    if (assetType == 'usStock' || RegExp(r'^[A-Z]{1,5}$').hasMatch(codeUpper)) {
      tags.add('美股');
    }
    if (assetType == 'hkStock' || (code.length == 5 && RegExp(r'^[0689]\d{4}$').hasMatch(code))) {
      if (!tags.contains('港股')) tags.add('港股');
    }
    if (assetType == 'aStock' || code.length == 6) {
      tags.add('A股');
    }
    
    // QDII 标签（海外基金）
    if (nameUpper.contains('QDII') || nameUpper.contains('海外') || 
        (nameUpper.contains('纳斯达克') && assetType == 'indexFund')) {
      tags.add('QDII');
    }
    
    return tags;
  }

  /// 判断一个价格是否像"总价"而非"单价"
  static bool _looksLikeTotalPrice(double price, double qty, String assetType) {
    if (qty <= 1) return false;
    final isFund = const {'indexFund', 'activeFund', 'bondFund', 'moneyFund'}.contains(assetType);
    if (isFund && price > 100 && qty > 10) return true;
    final unitGuess = price / qty;
    if (unitGuess > 0.1 && unitGuess < 10000 && price > 1000) return true;
    return false;
  }

  /// 根据股票代码判断币种（最高优先级）
  static String _detectCurrencyByCode(String code) {
    if (code.isEmpty || code == 'unknown') return '';
    
    final upperCode = code.toUpperCase();
    
    // 美股代码：1-5 个大写字母
    if (RegExp(r'^[A-Z]{1,5}$').hasMatch(upperCode)) {
      return 'USD';
    }
    
    // 港股代码：5 位数字，通常以 0、6、8、9 开头
    if (RegExp(r'^[0689]\d{4}$').hasMatch(code)) {
      return 'HKD';
    }
    
    // A 股代码：6 位数字
    if (RegExp(r'^\d{6}$').hasMatch(code)) {
      return 'CNY';
    }
    
    // 纯数字的 5 位码（某些系统表示美股）
    if (RegExp(r'^\d{5}$').hasMatch(code)) {
      return 'USD';
    }
    
    return '';
  }

  static String _getString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null && value.toString().trim().isNotEmpty) return value.toString().trim();
    }
    return '';
  }

  static List<String> _getStringList(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is List) {
        return value.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      }
      if (value is String && value.isNotEmpty) {
        // 尝试解析 JSON 数组格式
        try {
          final parsed = jsonDecode(value);
          if (parsed is List) {
            return parsed.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
          }
        } catch (_) {}
        // 尝试逗号分隔
        return value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }
    }
    return [];
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
  final double costPrice; // 允许负数（如做空、涡轮等）
  final double currentPrice;
  final double marketValue;
  final String assetType; // AI 识别的资产类型
  final String currency; // 币种: CNY/HKD/USD/EUR/GBP/JPY
  final List<String> aiTags; // AI 聚合标签
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
    this.aiTags = const [],
    this.warnings = const [],
  });

  ParsedHolding copyWith({
    String? code, String? name, double? quantity, double? costPrice,
    double? currentPrice, double? marketValue, String? assetType, String? currency,
    List<String>? aiTags, List<String>? warnings,
  }) {
    return ParsedHolding(
      code: code ?? this.code, name: name ?? this.name,
      quantity: quantity ?? this.quantity, costPrice: costPrice ?? this.costPrice,
      currentPrice: currentPrice ?? this.currentPrice, marketValue: marketValue ?? this.marketValue,
      assetType: assetType ?? this.assetType, currency: currency ?? this.currency,
      aiTags: aiTags ?? this.aiTags, warnings: warnings ?? this.warnings,
    );
  }

  /// 是否需要汇率转换
  bool get needsCurrencyConversion => currency != 'CNY' && currency.isNotEmpty;

  /// 是否有异常警告
  bool get hasWarnings => warnings.isNotEmpty;

  @override
  String toString() => 'ParsedHolding($code, $name, type=$assetType, currency=$currency, tags=$aiTags, mv=$marketValue${warnings.isNotEmpty ? ", warn=${warnings.join(";")}" : ""})';
}
