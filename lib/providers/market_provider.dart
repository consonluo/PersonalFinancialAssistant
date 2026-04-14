import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/api/eastmoney_api.dart';
import '../data/api/sina_finance_api.dart';
import '../data/api/fund_api.dart';
import '../data/models/market_data_model.dart';
import '../data/database/app_database.dart';
import 'database_provider.dart';
import 'holding_provider.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/asset_classifier.dart';
import 'package:drift/drift.dart';

/// 行情数据缓存 Provider
final marketDataProvider =
    StateNotifierProvider<MarketDataNotifier, Map<String, MarketDataModel>>(
        (ref) {
  return MarketDataNotifier(ref);
});

class MarketDataNotifier extends StateNotifier<Map<String, MarketDataModel>> {
  final Ref _ref;
  Timer? _refreshTimer;
  final _eastMoneyApi = EastMoneyApi();
  final _sinaApi = SinaFinanceApi();
  final _fundApi = FundApi();

  MarketDataNotifier(this._ref) : super({});

  /// 刷新所有持仓的行情
  Future<void> refreshAll() async {
    final holdingsAsync = _ref.read(allHoldingsProvider);
    final holdings = holdingsAsync.valueOrNull ?? [];
    if (holdings.isEmpty) return;

    // 分类收集代码
    final aCodes = <String>[];
    final hkCodes = <String>[];
    final usCodes = <String>[];
    final fundCodes = <String>[];

    for (final h in holdings) {
      final type = AssetType.values.firstWhere(
        (e) => e.name == h.assetType,
        orElse: () => AssetType.other,
      );
      switch (type) {
        case AssetType.aStock:
          aCodes.add(h.assetCode);
        case AssetType.hkStock:
          hkCodes.add(h.assetCode);
        case AssetType.usStock:
          usCodes.add(h.assetCode);
        case AssetType.deposit:
        case AssetType.realEstate:
        case AssetType.vehicle:
        case AssetType.wealth:
        case AssetType.other:
          break; // 不需要行情
        default:
          fundCodes.add(h.assetCode);
      }
    }

    final results = <MarketDataModel>[];

    // 并行请求
    final futures = <Future<List<MarketDataModel>>>[];
    if (aCodes.isNotEmpty || hkCodes.isNotEmpty) {
      futures.add(_eastMoneyApi.getQuotes([...aCodes, ...hkCodes]));
    }
    if (usCodes.isNotEmpty) {
      futures.add(_sinaApi.getQuotes(usCodes));
    }
    if (fundCodes.isNotEmpty) {
      futures.add(_fundApi.getQuotes(fundCodes));
    }

    final allResults = await Future.wait(futures);
    for (final r in allResults) {
      results.addAll(r);
    }

    // 更新状态
    final newState = Map<String, MarketDataModel>.from(state);
    for (final data in results) {
      newState[data.assetCode] = data;
    }
    state = newState;

    // 更新数据库缓存
    _updateDbCache(results);

    // 自动更新持仓表中的现价
    _updateHoldingPrices(results);
  }

  /// 将最新行情价格写入持仓表的 currentPrice 字段
  Future<void> _updateHoldingPrices(List<MarketDataModel> data) async {
    if (data.isEmpty) return;
    try {
      final db = _ref.read(databaseProvider);
      final holdings = _ref.read(allHoldingsProvider).valueOrNull ?? [];
      final priceMap = {for (final d in data) d.assetCode: d.price};

      for (final h in holdings) {
        final newPrice = priceMap[h.assetCode];
        if (newPrice != null && newPrice > 0 && newPrice != h.currentPrice) {
          await db.updateHolding(HoldingsCompanion(
            id: Value(h.id),
            accountId: Value(h.accountId),
            assetCode: Value(h.assetCode),
            assetName: Value(h.assetName),
            assetType: Value(h.assetType),
            quantity: Value(h.quantity),
            costPrice: Value(h.costPrice),
            currentPrice: Value(newPrice),
            updatedAt: Value(DateTime.now()),
          ));
        }
      }
    } catch (_) {}
  }

  Future<void> _updateDbCache(List<MarketDataModel> data) async {
    final db = _ref.read(databaseProvider);
    final entries = data.map((d) => MarketCacheCompanion(
      assetCode: Value(d.assetCode),
      price: Value(d.price),
      change: Value(d.change),
      changePercent: Value(d.changePercent),
      volume: Value(d.volume),
      name: Value(d.name),
      updatedAt: Value(d.updatedAt),
    )).toList();
    await db.upsertMarketCacheBatch(entries);
  }

  /// 启动自动刷新
  void startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: AppConstants.marketCacheTTLTrading),
      (_) => refreshAll(),
    );
    refreshAll(); // 立即刷新一次
  }

  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
