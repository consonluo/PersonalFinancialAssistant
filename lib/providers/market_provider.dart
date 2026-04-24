import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'snapshot_provider.dart';
import 'sync_provider.dart';
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
    var holdingsAsync = _ref.read(allHoldingsProvider);
    // StreamProvider 可能还没有数据，等待首次加载完成
    if (holdingsAsync.isLoading || (!holdingsAsync.hasValue && !holdingsAsync.hasError)) {
      debugPrint('[Market] holdings not ready, waiting...');
      await Future.delayed(const Duration(seconds: 2));
      holdingsAsync = _ref.read(allHoldingsProvider);
      if (!holdingsAsync.hasValue) {
        await Future.delayed(const Duration(seconds: 3));
        holdingsAsync = _ref.read(allHoldingsProvider);
      }
    }
    final holdings = holdingsAsync.valueOrNull ?? [];
    debugPrint('[Market] holdings count: ${holdings.length}');
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
        case AssetType.indexFund:
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
        case AssetType.activeFund:
        case AssetType.bondFund:
        case AssetType.moneyFund:
          fundCodes.add(h.assetCode);
        case AssetType.wealth:
        case AssetType.structuredDeposit:
        case AssetType.treasuryRepo:
        case AssetType.insurance:
        case AssetType.other:
          break;
      }
    }

    debugPrint('[Market] codes: A=${aCodes.length} HK=${hkCodes.length} US=${usCodes.length} Fund=${fundCodes.length}');
    if (aCodes.isNotEmpty) debugPrint('[Market] aCodes: $aCodes');
    if (fundCodes.isNotEmpty) debugPrint('[Market] fundCodes: $fundCodes');

    final results = <MarketDataModel>[];

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

    final allResults = await Future.wait(futures, eagerError: false);
    for (final r in allResults) {
      results.addAll(r);
    }
    debugPrint('[Market] total results: ${results.length}');

    // API 获取的代码集合
    final fetchedCodes = results.map((r) => r.assetCode).toSet();
    final allRequestedCodes = {...aCodes, ...hkCodes, ...usCodes, ...fundCodes};
    final missingCodes = allRequestedCodes.difference(fetchedCodes);

    // 对 API 失败的代码从数据库缓存回退
    if (missingCodes.isNotEmpty) {
      try {
        final db = _ref.read(databaseProvider);
        final cached = await db.getAllMarketCache();
        for (final c in cached) {
          if (missingCodes.contains(c.assetCode)) {
            results.add(MarketDataModel(
              assetCode: c.assetCode,
              name: c.name ?? c.assetCode,
              price: c.price ?? 0,
              change: c.change ?? 0,
              changePercent: c.changePercent ?? 0,
              volume: c.volume ?? 0,
              updatedAt: c.updatedAt ?? DateTime.now(),
            ));
          }
        }
        debugPrint('[Market] cache fallback: ${missingCodes.length} missing, recovered ${results.length - fetchedCodes.length}');
      } catch (e) {
        debugPrint('[Market] cache fallback error: $e');
      }
    }

    // 更新状态
    final newState = Map<String, MarketDataModel>.from(state);
    for (final data in results) {
      newState[data.assetCode] = data;
      final upper = data.assetCode.toUpperCase();
      if (upper != data.assetCode) newState[upper] = data;
    }
    state = newState;

    // 仅将新获取的数据更新到缓存（不用缓存覆盖缓存）
    final freshResults = results.where((r) => fetchedCodes.contains(r.assetCode)).toList();
    _updateDbCache(freshResults);

    // 自动更新持仓表中的现价
    await _updateHoldingPrices(results);

    // 自动纠正分类：将 assetType 为 "other" 但分类器能识别的持仓重新分类
    await _reclassifyMistyped();

    // 价格更新后重新计算今日快照；若本次从接口拿到了最新行情，则强制覆盖今日点（不受 1% 阈值限制），并防抖上传 WebDAV（含 assetSnapshots，便于多设备看历史走势）
    try {
      final db = _ref.read(databaseProvider);
      final gotLiveQuotes = fetchedCodes.isNotEmpty;
      await SnapshotService(db).takeSnapshotIfNeeded(forceUpdateToday: gotLiveQuotes);
      if (gotLiveQuotes) {
        _ref.invalidate(snapshotListProvider);
        try {
          _ref.read(autoSyncProvider).triggerAutoSync();
        } catch (_) {}
      }
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

  static const _classifierVersion = 3; // 每次分类器规则变更时递增

  /// 自动纠正分类：旧类型名迁移 + "other" 类型重新识别 + 版本化全量重分类
  Future<void> _reclassifyMistyped() async {
    try {
      final db = _ref.read(databaseProvider);
      final holdings = _ref.read(allHoldingsProvider).valueOrNull ?? [];
      var fixed = 0;

      // 检查分类器版本，版本变更时对所有持仓重新跑分类器
      final prefs = await SharedPreferences.getInstance();
      final storedVersion = prefs.getInt('classifier_version') ?? 0;
      final fullRescan = storedVersion < _classifierVersion;

      for (final h in holdings) {
        String? newType;

        // 1) 旧枚举名迁移（indexETF→indexFund 等）
        final legacy = AssetType.legacyNameMap[h.assetType];
        if (legacy != null) {
          final better = AssetClassifier.classify(h.assetCode, h.assetName);
          newType = (better != AssetType.other) ? better.name : legacy;
        }

        // 2) "other" 类型尝试自动识别
        if (newType == null && h.assetType == AssetType.other.name) {
          final better = AssetClassifier.classify(h.assetCode, h.assetName);
          if (better != AssetType.other) newType = better.name;
        }

        // 3) 分类器版本升级 → 全量重新分类
        if (newType == null && fullRescan) {
          final better = AssetClassifier.classify(h.assetCode, h.assetName);
          if (better != AssetType.other && better.name != h.assetType) {
            newType = better.name;
          }
        }

        if (newType != null && newType != h.assetType) {
          await db.updateHolding(HoldingsCompanion(
            id: Value(h.id),
            accountId: Value(h.accountId),
            assetCode: Value(h.assetCode),
            assetName: Value(h.assetName),
            assetType: Value(newType),
            quantity: Value(h.quantity),
            costPrice: Value(h.costPrice),
            currentPrice: Value(h.currentPrice),
            tags: Value(h.tags),
            notes: Value(h.notes),
            createdAt: Value(h.createdAt),
            updatedAt: Value(h.updatedAt),
          ));
          fixed++;
          debugPrint('[Market] reclassified "${h.assetName}": ${h.assetType} → $newType');
        }
      }

      if (fullRescan) await prefs.setInt('classifier_version', _classifierVersion);
      debugPrint('[Market] reclassify: scanned ${holdings.length}, fixed $fixed${fullRescan ? ' (full rescan v$_classifierVersion)' : ''}');
    } catch (e) {
      debugPrint('[Market] reclassify error: $e');
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
