import 'dart:async';
import 'package:flutter/foundation.dart';
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
import '../core/utils/snapshot_service.dart';
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
        case AssetType.gold:
          if (_isExchangeListedETF(h.assetCode)) {
            aCodes.add(h.assetCode);
          } else if (RegExp(r'^\d{6}$').hasMatch(h.assetCode)) {
            fundCodes.add(h.assetCode);
          }
        case AssetType.indexETF:
        case AssetType.nasdaqETF:
          if (_isExchangeListedETF(h.assetCode)) {
            aCodes.add(h.assetCode);
          } else {
            fundCodes.add(h.assetCode);
          }
        case AssetType.deposit:
        case AssetType.fixedDeposit:
        case AssetType.largeDeposit:
        case AssetType.noticeDeposit:
        case AssetType.realEstate:
        case AssetType.vehicle:
        case AssetType.wealth:
        case AssetType.structuredDeposit:
        case AssetType.treasuryRepo:
        case AssetType.insurance:
        case AssetType.other:
          break;
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

    // 更新状态（同时存原始代码和去后缀的代码，确保匹配）
    final newState = Map<String, MarketDataModel>.from(state);
    for (final data in results) {
      newState[data.assetCode] = data;
      // 美股/港股等可能持仓代码带后缀，API返回不带
      final upper = data.assetCode.toUpperCase();
      if (upper != data.assetCode) newState[upper] = data;
    }
    state = newState;

    // 更新数据库缓存
    _updateDbCache(results);

    // 自动更新持仓表中的现价
    await _updateHoldingPrices(results);

    // 价格更新后重新计算今日快照
    try {
      final db = _ref.read(databaseProvider);
      await SnapshotService(db).takeSnapshotIfNeeded();
    } catch (_) {}
  }

  /// 判断是否为交易所上市ETF（走股票行情接口而非基金净值接口）
  static bool _isExchangeListedETF(String code) {
    final pure = code.replaceAll(
        RegExp(r'\.(SH|SZ|OF)$', caseSensitive: false), '');
    if (!RegExp(r'^\d{6}$').hasMatch(pure)) return false;
    return pure.startsWith('51') ||
        pure.startsWith('15') ||
        pure.startsWith('56') ||
        pure.startsWith('52') ||
        pure.startsWith('58');
  }

  /// 将最新行情价格写入持仓表的 currentPrice 字段
  Future<void> _updateHoldingPrices(List<MarketDataModel> data) async {
    if (data.isEmpty) return;
    try {
      final db = _ref.read(databaseProvider);
      final holdings = _ref.read(allHoldingsProvider).valueOrNull ?? [];
      final priceMap = {for (final d in data) d.assetCode: d.price};

      for (final h in holdings) {
        // 精确匹配或去后缀匹配（美股代码可能带.US/.O/.N后缀）
        final code = h.assetCode;
        final normalizedCode = code.replaceAll(RegExp(r'\.(US|O|N|HK|SH|SZ|OF)$', caseSensitive: false), '').toUpperCase();
        final newPrice = priceMap[code] ?? priceMap[normalizedCode];
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
            tags: Value(h.tags),
            notes: Value(h.notes),
            createdAt: Value(h.createdAt),
            updatedAt: Value(DateTime.now()),
          ));
        }
      }
    } catch (e) {
      debugPrint('[MarketData] 更新持仓现价失败: $e');
    }
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
