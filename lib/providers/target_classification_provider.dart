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

输出要求（必须遵守，否则解析失败）：
- 只输出一个 JSON 对象，不要 markdown 代码块、不要前后解释文字
- 每个 holdings 项的 reason 不超过 10 个字，description 不超过 20 个字，以控制总长度

返回格式示例：
{"groups":[{"name":"分类名","description":"短描述","holdings":[{"id":"持仓uuid","reason":"短理由"}]}]}''';
  }

  static Map<String, dynamic> _parseGroupsJson(String raw) {
    var s = raw
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .trim();
    final m = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', caseSensitive: false).firstMatch(s);
    if (m != null) s = m.group(1)!.trim();
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw FormatException('响应中未找到 JSON 对象');
    }
    s = s.substring(start, end + 1);
    return jsonDecode(s) as Map<String, dynamic>;
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
    final aiGroups = data['groups'] as List? ?? [];

    double grandTotal = 0;
    final enriched = <_TempGroup>[];

    for (final g in aiGroups) {
      final items = <TargetHolding>[];
      double groupMv = 0, groupPnl = 0;

      for (final item in (g['holdings'] as List? ?? [])) {
        final id = item['id'] as String? ?? '';
        final reason = item['reason'] as String? ?? '';
        final h = holdingMap[id];
        if (h == null) continue;

        final mkt = marketData[h.assetCode];
        final price = mkt?.price ?? h.currentPrice;
        final mv = h.quantity * price;
        final pnl = (price - h.costPrice) * h.quantity;
        final pnlPct = h.costPrice > 0 ? (price - h.costPrice) / h.costPrice * 100 : 0.0;

        items.add(TargetHolding(
          id: id, name: h.assetName, code: h.assetCode,
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
