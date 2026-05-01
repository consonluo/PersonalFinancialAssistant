import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/ai_service.dart';
import 'holding_provider.dart';
import 'market_provider.dart';

class TargetGroup {
  final String name;
  final String description;
  final List<TargetHolding> holdings;
  final double totalMarketValue;
  final double totalPnl;
  final double proportion;

  const TargetGroup({
    required this.name,
    required this.description,
    required this.holdings,
    required this.totalMarketValue,
    required this.totalPnl,
    required this.proportion,
  });
}

class TargetHolding {
  final String id;
  final String name;
  final String code;
  final String reason;
  final double marketValue;
  final double pnl;
  final double pnlPercent;

  const TargetHolding({
    required this.id,
    required this.name,
    required this.code,
    required this.reason,
    required this.marketValue,
    required this.pnl,
    required this.pnlPercent,
  });
}

class TargetClassificationState {
  final List<TargetGroup> groups;
  final bool isLoading;
  final String? error;
  final String streamText;
  final DateTime? lastUpdated;

  const TargetClassificationState({
    this.groups = const [],
    this.isLoading = false,
    this.error,
    this.streamText = '',
    this.lastUpdated,
  });

  TargetClassificationState copyWith({
    List<TargetGroup>? groups,
    bool? isLoading,
    String? error,
    String? streamText,
    DateTime? lastUpdated,
  }) => TargetClassificationState(
    groups: groups ?? this.groups,
    isLoading: isLoading ?? this.isLoading,
    error: error,
    streamText: streamText ?? this.streamText,
    lastUpdated: lastUpdated ?? this.lastUpdated,
  );
}

class TargetClassificationNotifier extends StateNotifier<TargetClassificationState> {
  final Ref _ref;
  static const _cacheKey = 'target_classification_cache';

  /// 构建「标的分类」AI 提示词（供设置里预览编辑）
  static String buildTargetClassificationPrompt(List<Map<String, dynamic>> holdingList) {
    return '''你是专业的投资组合分析师。请严格按照下列预定义标的分类对持仓进行归类。

持仓列表：
${jsonEncode(holdingList)}

===== 标的分类规则（必须严格遵守） =====

预定义分类（只能用这些名称，不要自创）：
1. "纳斯达克" — 所有跟踪纳斯达克100/纳指相关的基金和ETF（包括QDII纳指联接）
2. "红利/高股息" — 所有红利、高股息、红利低波、红利质量主题
3. "港股" — 所有港股通ETF、港股主题基金
4. "A股宽基" — 跟踪沪深300/中证500/中证1000/上证50/A500等宽基指数
5. "消费" — 消费主题（含白酒）
6. "科技/成长" — 科技、半导体、新能源、AI、成长主题
7. "全球/海外" — QDII全球配置、海外市场（非纳指的海外基金）
8. "自由现金流" — 自由现金流策略主题
9. "债券固收" — 债券基金、纯债、信用债
10. "货币现金" — 货币基金、现金管理
11. "银行理财" — 银行理财产品
12. "存款" — 活期/定期存款、大额存单
13. "其他" — 无法归入以上分类的

关键规则：
- 同一标的的所有产品必须归入同一分类（如所有纳指相关产品都归"纳斯达克"，不能分散到"宽基"或"海外"）
- 名称含"纳指""纳斯达克""NASDAQ"的一律归"纳斯达克"
- 名称含"红利""高股息""分红"的一律归"红利/高股息"
- 名称含"港股通""港股""恒生"的一律归"港股"
- 如果某个预定义分类没有对应持仓，则不输出该分类

输出要求（必须严格遵守，否则解析失败）：
- 只输出一个合法的 JSON 对象，**禁止**任何前后解释、说明、markdown 代码块（不要 ```json）
- 字符串必须使用双引号 ""，不要使用单引号 ''
- 不要在最后一个元素后添加多余逗号
- 不要写注释（// 或 /* */）
- 每个 holdings 项的 reason 不超过 10 个字，description 不超过 20 个字
- id 字段必须使用上述持仓列表中实际存在的 uuid，不要自创

第一个字符必须是 {，最后一个字符必须是 }。

返回格式示例：
{"groups":[{"name":"分类名","description":"短描述","holdings":[{"id":"持仓uuid","reason":"短理由"}]}]}''';
  }

  /// 鲁棒地从 AI 响应中提取并解析 JSON 对象
  ///
  /// 处理常见问题：
  /// - markdown 代码块包裹（```json ... ```）
  /// - 前后夹杂自然语言/解释文字
  /// - 尾部多余逗号 `,}` `,]`
  /// - 单引号字符串
  /// - 截断的 JSON（流式过早结束）
  static Map<String, dynamic> _parseGroupsJson(String raw) {
    // 1. 先尝试提取 markdown 代码块内容
    var s = raw.trim();
    final mdMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', caseSensitive: false).firstMatch(s);
    if (mdMatch != null) {
      s = mdMatch.group(1)!.trim();
    } else {
      // 没有完整 markdown 包裹的情况下，去掉残留的 ```json / ```
      s = s
          .replaceAll(RegExp(r'```json\s*', caseSensitive: false), '')
          .replaceAll(RegExp(r'```\s*'), '')
          .trim();
    }

    // 2. 用括号计数找到第一个完整闭合的 JSON 对象
    final extracted = _extractFirstJsonObject(s);
    if (extracted == null) {
      throw FormatException('响应中未找到完整的 JSON 对象');
    }
    s = extracted;

    // 3. 直接尝试解析
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      // 4. 容错修复后重试
      var fixed = s
          // 去掉对象/数组尾部多余逗号
          .replaceAll(RegExp(r',(\s*[}\]])'), r'$1')
          // 去掉行尾的 // 注释
          .replaceAll(RegExp(r'//[^\n]*'), '');
      try {
        return jsonDecode(fixed) as Map<String, dynamic>;
      } catch (e) {
        // 5. 最后尝试：把单引号字符串转为双引号（仅当看起来是 JSON 形态）
        fixed = _replaceUnquotedSingleStrings(fixed);
        return jsonDecode(fixed) as Map<String, dynamic>;
      }
    }
  }

  /// 用括号计数从字符串中提取首个完整闭合的 JSON 对象
  static String? _extractFirstJsonObject(String s) {
    final start = s.indexOf('{');
    if (start < 0) return null;

    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < s.length; i++) {
      final c = s[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (c == r'\') {
        escape = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          return s.substring(start, i + 1);
        }
      }
    }
    // 如果整个字符串没有完整闭合，返回 null（AI 输出被截断）
    return null;
  }

  /// 把不在双引号上下文中的单引号字符串改为双引号
  /// 简单实现：仅处理形如 'xxx': 或 :'xxx' 这种模式
  static String _replaceUnquotedSingleStrings(String s) {
    // 把 'xxx' 替换为 "xxx"，但仅当 xxx 内部没有双引号时
    return s.replaceAllMapped(
      RegExp(r"'([^'\\]*(?:\\.[^'\\]*)*)'"),
      (m) {
        final content = m.group(1) ?? '';
        if (content.contains('"')) return m.group(0)!;
        return '"$content"';
      },
    );
  }

  TargetClassificationNotifier(this._ref) : super(const TargetClassificationState()) {
    _loadFromCache();
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final groups = _parseAndEnrichGroups(data);
      if (groups.isNotEmpty) {
        final ts = data['updatedAt'] as String?;
        state = state.copyWith(
          groups: groups,
          lastUpdated: ts != null ? DateTime.tryParse(ts) : null,
        );
      }
    } catch (e) {
      debugPrint('[TargetClassify] cache load error: $e');
    }
  }

  List<TargetGroup> _parseAndEnrichGroups(Map<String, dynamic> data) {
    final holdings = _ref.read(allHoldingsProvider).valueOrNull ?? [];
    final marketData = _ref.read(marketDataProvider);
    if (holdings.isEmpty) return [];

    final holdingMap = {for (final h in holdings) h.id: h};
    // 按 assetCode 跨账户合并：相同代码的持仓在 AI 分类里只展示一行
    final codeAggregates = <String, _CodeAgg>{};
    for (final h in holdings) {
      final key = h.assetCode.isNotEmpty ? h.assetCode : '__id:${h.id}';
      final mkt = marketData[h.assetCode];
      final price = mkt?.price ?? h.currentPrice;
      codeAggregates.putIfAbsent(key, () => _CodeAgg(
        firstId: h.id, name: h.assetName, code: h.assetCode, price: price,
      ));
      final acc = codeAggregates[key]!;
      acc.qty += h.quantity;
      acc.totalCost += h.quantity * h.costPrice;
      acc.price = price;
    }
    final idToCodeKey = {
      for (final h in holdings)
        h.id: h.assetCode.isNotEmpty ? h.assetCode : '__id:${h.id}'
    };

    final aiGroups = data['groups'] as List? ?? [];

    double grandTotal = 0;
    final enriched = <_TempGroup>[];

    for (final g in aiGroups) {
      final items = <TargetHolding>[];
      final seenCodes = <String>{};
      double groupMv = 0, groupPnl = 0;

      for (final item in (g['holdings'] as List? ?? [])) {
        final id = item['id'] as String? ?? '';
        final reason = item['reason'] as String? ?? '';
        final h = holdingMap[id];
        if (h == null) continue;

        // 同一组内若 AI 给出多条相同代码，只保留第一条
        final codeKey = idToCodeKey[id] ?? '__id:$id';
        if (seenCodes.contains(codeKey)) continue;
        seenCodes.add(codeKey);

        final agg = codeAggregates[codeKey];
        if (agg == null) continue;

        final mv = agg.qty * agg.price;
        final pnl = mv - agg.totalCost;
        final avgCost = agg.qty != 0 ? agg.totalCost / agg.qty : 0.0;
        final pnlPct = avgCost > 0 ? (agg.price - avgCost) / avgCost * 100 : 0.0;

        items.add(TargetHolding(
          id: agg.firstId, name: agg.name, code: agg.code,
          reason: reason, marketValue: mv, pnl: pnl, pnlPercent: pnlPct,
        ));
        groupMv += mv;
        groupPnl += pnl;
      }
      if (items.isEmpty) continue;
      grandTotal += groupMv;
      enriched.add(_TempGroup(
        name: g['name'] as String? ?? '未分类',
        description: g['description'] as String? ?? '',
        holdings: items, mv: groupMv, pnl: groupPnl,
      ));
    }

    return enriched.map((g) => TargetGroup(
      name: g.name, description: g.description,
      holdings: g.holdings..sort((a, b) => b.marketValue.compareTo(a.marketValue)),
      totalMarketValue: g.mv, totalPnl: g.pnl,
      proportion: grandTotal > 0 ? g.mv / grandTotal * 100 : 0,
    )).toList()..sort((a, b) => b.totalMarketValue.compareTo(a.totalMarketValue));
  }

  /// 流式分类 — 实时显示 AI 输出，完成后解析 JSON
  Future<void> classifyStream({String? promptOverride}) async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: null, streamText: '');

    try {
      final holdings = _ref.read(allHoldingsProvider).valueOrNull ?? [];
      if (holdings.isEmpty) {
        state = state.copyWith(isLoading: false, error: '暂无持仓数据');
        return;
      }

      final holdingList = holdings.map((h) => {
        'id': h.id,
        'code': h.assetCode,
        'name': h.assetName,
        'type': h.assetType,
      }).toList();

      final prompt = promptOverride ?? buildTargetClassificationPrompt(holdingList);

      final buffer = StringBuffer();
      await for (final delta in AiService.chatStream(prompt)) {
        buffer.write(delta);
        state = state.copyWith(streamText: buffer.toString());
      }

      final response = buffer.toString();
      final parsed = _parseGroupsJson(response);

      final now = DateTime.now();
      parsed['updatedAt'] = now.toIso8601String();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(parsed));

      final groups = _parseAndEnrichGroups(parsed);
      state = TargetClassificationState(
        groups: groups, lastUpdated: now,
      );
    } on AiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      debugPrint('[TargetClassify] stream error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'AI 分类失败：$e\n若持仓较多，可在设置中精简提示词后重试。',
      );
    }
  }

  /// 非流式分类（保留兼容）
  Future<void> classify({String? promptOverride}) async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: null, streamText: '');

    try {
      final holdings = _ref.read(allHoldingsProvider).valueOrNull ?? [];
      if (holdings.isEmpty) {
        state = state.copyWith(isLoading: false, error: '暂无持仓数据');
        return;
      }

      final holdingList = holdings.map((h) => {
        'id': h.id,
        'code': h.assetCode,
        'name': h.assetName,
        'type': h.assetType,
      }).toList();

      final prompt = promptOverride ?? buildTargetClassificationPrompt(holdingList);

      // 标的分类必须得到完整可解析 JSON；流式拼接易截断、且逐 token 刷新 UI 会造成卡顿
      final response = await AiService.chat(prompt).timeout(
        const Duration(seconds: 180),
        onTimeout: () => throw AiException('请求超时，请检查网络或稍后再试'),
      );

      final parsed = _parseGroupsJson(response);

      final now = DateTime.now();
      parsed['updatedAt'] = now.toIso8601String();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(parsed));

      final groups = _parseAndEnrichGroups(parsed);
      state = TargetClassificationState(
        groups: groups, lastUpdated: now,
      );
    } on AiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      debugPrint('[TargetClassify] error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'AI 分类失败：$e\n若持仓较多，可在设置中精简提示词后重试。',
      );
    }
  }
}

final targetClassificationProvider =
    StateNotifierProvider<TargetClassificationNotifier, TargetClassificationState>(
  (ref) => TargetClassificationNotifier(ref),
);

class _TempGroup {
  final String name, description;
  final List<TargetHolding> holdings;
  final double mv, pnl;
  _TempGroup({required this.name, required this.description,
    required this.holdings, required this.mv, required this.pnl});
}

/// 按 assetCode 合并持仓的临时聚合
class _CodeAgg {
  final String firstId;
  final String name;
  final String code;
  double qty = 0;
  double totalCost = 0;
  double price;
  _CodeAgg({
    required this.firstId,
    required this.name,
    required this.code,
    required this.price,
  });
}
