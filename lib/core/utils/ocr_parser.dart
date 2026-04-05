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
      final quantity = _getDouble(item, ['quantity', 'qty', 'shares', 'amount']);
      final costPrice = _getDouble(item, ['costPrice', 'cost', 'avgCost', 'buyPrice']);
      final currentPrice = _getDouble(item, ['currentPrice', 'price', 'lastPrice', 'latestPrice']);
      final marketValue = _getDouble(item, ['marketValue', 'value', 'totalValue']);
      final assetType = _getString(item, ['assetType', 'type', 'category']);

      if (code.isEmpty && name.isEmpty) continue;

      final computedMv = marketValue > 0
          ? marketValue
          : (quantity > 0 && currentPrice > 0 ? quantity * currentPrice : 0.0);

      results.add(ParsedHolding(
        code: code.isNotEmpty ? code : 'unknown',
        name: name.isNotEmpty ? name : code,
        quantity: quantity,
        costPrice: costPrice,
        currentPrice: currentPrice,
        marketValue: computedMv,
        assetType: assetType.isNotEmpty ? assetType : '',
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

  const ParsedHolding({
    required this.code,
    required this.name,
    required this.quantity,
    required this.costPrice,
    required this.currentPrice,
    required this.marketValue,
    this.assetType = '',
  });

  ParsedHolding copyWith({
    String? code, String? name, double? quantity, double? costPrice,
    double? currentPrice, double? marketValue, String? assetType,
  }) {
    return ParsedHolding(
      code: code ?? this.code, name: name ?? this.name,
      quantity: quantity ?? this.quantity, costPrice: costPrice ?? this.costPrice,
      currentPrice: currentPrice ?? this.currentPrice, marketValue: marketValue ?? this.marketValue,
      assetType: assetType ?? this.assetType,
    );
  }

  @override
  String toString() => 'ParsedHolding($code, $name, type=$assetType, mv=$marketValue)';
}
