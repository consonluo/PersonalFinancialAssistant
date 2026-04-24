import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/ai_service.dart';
import 'holding_provider.dart';
import 'market_provider.dart';

/// AI 标的分类 — 按投资标的（而非产品形态）对持仓进行聚合
/// 例如：科技/成长、红利/价值、纳斯达克、沪深300、货币/现金 等

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
  final DateTime? lastUpdated;

  const TargetClassificationState({
    this.groups = const [],
    this.isLoading = false,
    this.error,
    this.lastUpdated,
  });

  TargetClassificationState copyWith({
    List<TargetGroup>? groups,
    bool? isLoading,
    String? error,
    DateTime? lastUpdated,
  }) => TargetClassificationState(
    groups: groups ?? this.groups,
    isLoading: isLoading ?? this.isLoading,
    error: error,
    lastUpdated: lastUpdated ?? this.lastUpdated,
  );
}

class TargetClassificationNotifier extends StateNotifier<TargetClassificationState> {
  final Ref _ref;
  static const _cacheKey = 'target_classification_cache';

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

  Future<void> classify() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: null);

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

      final prompt = '''你是专业的投资组合分析师。请按照**投资标的/策略**对以下持仓进行分类聚合。

持仓列表：
${jsonEncode(holdingList)}

分类维度（按实际投资标的，不按产品形态）：
- 例如：宽基指数（沪深300/中证500）、科技/半导体、消费、医药、新能源、纳斯达克/美股、红利/高股息、债券固收、货币现金、银行理财、黄金贵金属、房产 等
- 如果某只基金跟踪特定指数，按该指数的标的归类（如"纳指ETF"归入"纳斯达克"，"红利ETF"归入"红利/高股息"）
- 同一只持仓只能归入一个分类
- 存款/理财按其性质归类（活期存款→货币现金，理财→银行理财）

返回严格JSON（不要markdown），格式如下：
{"groups":[{"name":"分类名","description":"一句话描述该分类的特征","holdings":[{"id":"持仓id","reason":"归类理由"}]}]}''';

      final result = await AiService.chat(prompt);

      final cleaned = result
          .replaceAll(RegExp(r'```json\s*'), '')
          .replaceAll(RegExp(r'```\s*'), '')
          .trim();
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;

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
      state = state.copyWith(isLoading: false, error: 'AI 分类失败：$e');
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
