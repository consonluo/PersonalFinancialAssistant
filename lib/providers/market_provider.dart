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
    StateNotifierProvider<MarketDataNotifier, Map<String, MarketDataModel>>((
      ref,
    ) {
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
    if (holdingsAsync.isLoading ||
        (!holdingsAsync.hasValue && !holdingsAsync.hasError)) {
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
    final codeCurrencyHints = <String, String>{};

    for (final h in holdings) {
      if (h.quantity == 0) continue;
      final code = h.assetCode;
      if (code.isNotEmpty && h.currency.isNotEmpty) {
        codeCurrencyHints[_normalizeCodeKey(code)] = h.currency.toUpperCase();
      }
      final type = AssetType.values.firstWhere(
        (e) => e.name == h.assetType,
        orElse: () => AssetType.other,
      );

      // 判断代码形态
      final pureDigit = code.replaceAll(
        RegExp(r'\.(SH|SZ|HK|OF|US)$', caseSensitive: false),
        '',
      );
      final is6Digit = RegExp(r'^\d{6}$').hasMatch(pureDigit);
      final is5Digit = RegExp(r'^\d{1,5}$').hasMatch(pureDigit);
      final isUsLike =
          RegExp(r'^[A-Za-z]{1,5}$').hasMatch(pureDigit) ||
          code.toUpperCase().endsWith('.US');
      final isHkLike = is5Digit || code.toUpperCase().endsWith('.HK');

      var routed = false;
      switch (type) {
        case AssetType.aStock:
          aCodes.add(code);
          routed = true;
        case AssetType.hkStock:
          hkCodes.add(code);
          routed = true;
        case AssetType.usStock:
          usCodes.add(code);
          routed = true;
        case AssetType.gold:
          if (_isExchangeListedETF(code)) {
            aCodes.add(code);
            routed = true;
          } else if (is6Digit) {
            fundCodes.add(code);
            routed = true;
          }
        case AssetType.indexFund:
        case AssetType.activeFund:
        case AssetType.bondFund:
        case AssetType.moneyFund:
          if (_isExchangeListedETF(code)) {
            aCodes.add(code);
            routed = true;
          } else if (isUsLike) {
            usCodes.add(code);
            routed = true;
          } else if (isHkLike) {
            hkCodes.add(code);
            routed = true;
          } else if (is6Digit) {
            fundCodes.add(code);
            routed = true;
          }
        case AssetType.deposit:
        case AssetType.fixedDeposit:
        case AssetType.largeDeposit:
        case AssetType.noticeDeposit:
          if (is6Digit) {
            fundCodes.add(code);
            routed = true;
          }
        case AssetType.realEstate:
        case AssetType.vehicle:
        case AssetType.wealth:
        case AssetType.structuredDeposit:
        case AssetType.treasuryRepo:
        case AssetType.insurance:
        case AssetType.other:
          break;
      }

      // 兜底：资产类型被误分时，按代码形态补路由
      if (!routed) {
        if (isUsLike) {
          usCodes.add(code);
        } else if (isHkLike) {
          hkCodes.add(code);
        } else if (is6Digit) {
          aCodes.add(code);
        }
      }
    }

    final aCodesDedup = aCodes.toSet().toList();
    final hkCodesDedup = hkCodes.toSet().toList();
    final usCodesDedup = usCodes.toSet().toList();
    final fundCodesDedup = fundCodes.toSet().toList();

    debugPrint(
      '[Market] codes: A=${aCodesDedup.length} HK=${hkCodesDedup.length} US=${usCodesDedup.length} Fund=${fundCodesDedup.length}',
    );
    if (aCodesDedup.isNotEmpty) debugPrint('[Market] aCodes: $aCodesDedup');
    if (fundCodesDedup.isNotEmpty) {
      debugPrint('[Market] fundCodes: $fundCodesDedup');
    }

    final results = <MarketDataModel>[];
    final cnTrading = _isCnTradingNow();
    final hkTrading = _isHkTradingNow();
    final usTrading = _isUsTradingNow();
    debugPrint(
      '[Market] trading session: CN=$cnTrading HK=$hkTrading US=$usTrading',
    );

    final futures = <Future<List<MarketDataModel>>>[];
    final eastLiveCodes = <String>[
      if (cnTrading) ...aCodesDedup,
      if (hkTrading) ...hkCodesDedup,
    ];
    if (eastLiveCodes.isNotEmpty) {
      futures.add(
        _fetchWithRetry(() => _eastMoneyApi.getQuotes(eastLiveCodes)),
      );
    }
    if (usTrading && usCodesDedup.isNotEmpty) {
      futures.add(_fetchWithRetry(() => _sinaApi.getQuotes(usCodesDedup)));
    }
    // 基金净值接口不严格区分交易时段，统一尝试最新可得值。
    if (fundCodesDedup.isNotEmpty) {
      futures.add(_fetchWithRetry(() => _fundApi.getQuotes(fundCodesDedup)));
    }

    final allResults = await Future.wait(futures, eagerError: false);
    for (final r in allResults) {
      results.addAll(r);
    }
    debugPrint('[Market] total results: ${results.length}');

    // API 获取的代码集合
    final fetchedCodes = results.map((r) => r.assetCode).toSet();
    final fetchedCodeKeys =
        results
            .expand((r) => _codeAliases(r.assetCode))
            .map(_normalizeCodeKey)
            .toSet();
    // 美股兜底：新浪拿不到时，再尝试东财（部分美股可返回）
    final missingUsCodes =
        usCodesDedup
            .where((c) => !fetchedCodeKeys.contains(_normalizeCodeKey(c)))
            .toList();
    if (usTrading && missingUsCodes.isNotEmpty) {
      try {
        final usFallback = await _fetchWithRetry(
          () => _eastMoneyApi.getQuotes(missingUsCodes),
          attempts: 2,
        );
        if (usFallback.isNotEmpty) {
          results.addAll(usFallback);
          fetchedCodes.addAll(usFallback.map((e) => e.assetCode));
          fetchedCodeKeys.addAll(
            usFallback
                .expand((e) => _codeAliases(e.assetCode))
                .map(_normalizeCodeKey),
          );
          debugPrint(
            '[Market] us fallback by eastmoney: ${usFallback.length}/${missingUsCodes.length}',
          );
        }
      } catch (e) {
        debugPrint('[Market] us fallback failed: $e');
      }
    }

    final allRequestedCodes = {
      ...aCodesDedup,
      ...hkCodesDedup,
      ...usCodesDedup,
      ...fundCodesDedup,
    };
    var missingCodes =
        allRequestedCodes
            .where((c) => !fetchedCodeKeys.contains(_normalizeCodeKey(c)))
            .toSet();

    // 单只补拉：批量失败后逐只再尝试，提升成功率
    final openMarketMissing =
        missingCodes.where((code) {
          if (fundCodesDedup.contains(code)) return true;
          if (usCodesDedup.contains(code)) return usTrading;
          if (hkCodesDedup.contains(code)) return hkTrading;
          if (aCodesDedup.contains(code)) return cnTrading;
          return false;
        }).toSet();
    if (openMarketMissing.isNotEmpty) {
      final recoveredSingles = await _fetchSinglesForMissing(
        missingCodes: openMarketMissing,
        usCodes: usCodesDedup.toSet(),
        fundCodes: fundCodesDedup.toSet(),
      );
      if (recoveredSingles.isNotEmpty) {
        results.addAll(recoveredSingles);
        fetchedCodes.addAll(recoveredSingles.map((e) => e.assetCode));
        fetchedCodeKeys.addAll(
          recoveredSingles
              .expand((e) => _codeAliases(e.assetCode))
              .map(_normalizeCodeKey),
        );
        missingCodes =
            allRequestedCodes
                .where((c) => !fetchedCodeKeys.contains(_normalizeCodeKey(c)))
                .toSet();
        debugPrint(
          '[Market] single fallback recovered: ${recoveredSingles.length}',
        );
      }
    }

    // 第二优先级：最近交易日收盘价（接口）
    final closeCandidates =
        missingCodes.where((code) {
          if (aCodesDedup.contains(code)) return !cnTrading;
          if (hkCodesDedup.contains(code)) return !hkTrading;
          if (usCodesDedup.contains(code)) return !usTrading;
          return false;
        }).toList();
    if (closeCandidates.isNotEmpty) {
      final closeFallback = await _fetchWithRetry(
        () => _eastMoneyApi.getLastCloseQuotes(closeCandidates),
        attempts: 2,
      );
      if (closeFallback.isNotEmpty) {
        results.addAll(closeFallback);
        fetchedCodes.addAll(closeFallback.map((e) => e.assetCode));
        fetchedCodeKeys.addAll(
          closeFallback
              .expand((e) => _codeAliases(e.assetCode))
              .map(_normalizeCodeKey),
        );
        missingCodes =
            allRequestedCodes
                .where((c) => !fetchedCodeKeys.contains(_normalizeCodeKey(c)))
                .toSet();
        debugPrint(
          '[Market] close fallback recovered: ${closeFallback.length}',
        );
      }
    }

    // 收盘价接口在部分网络环境可能不可达，降级用常规报价接口兜底最近可用价。
    if (missingCodes.isNotEmpty) {
      final aCloseCandidates =
          missingCodes.where((c) => aCodesDedup.contains(c) && !cnTrading).toList();
      final hkCloseCandidates =
          missingCodes.where((c) => hkCodesDedup.contains(c) && !hkTrading).toList();
      final usCloseCandidates =
          missingCodes.where((c) => usCodesDedup.contains(c) && !usTrading).toList();

      final closeByQuote = <MarketDataModel>[];
      // 非交易时段收盘回退：updatedAt 使用各市场最近交易日，不信任 API 返回的时间戳
      // （API 在休市时可能返回今日凌晨时间，导致界面显示错误日期）
      final cnLastClose = _lastMarketCloseDay(isUs: false);
      final usLastClose = _lastMarketCloseDay(isUs: true);

      if (aCloseCandidates.isNotEmpty || hkCloseCandidates.isNotEmpty) {
        final east = await _fetchWithRetry(
          () => _eastMoneyApi.getQuotes([
            ...aCloseCandidates,
            ...hkCloseCandidates,
          ]),
          attempts: 2,
        );
        closeByQuote.addAll(
          east.map(
            (e) => MarketDataModel(
              assetCode: e.assetCode,
              name: e.name,
              price: e.price,
              change: e.change,
              changePercent: e.changePercent,
              volume: e.volume,
              updatedAt: cnLastClose,
              currency: e.currency,
              source: MarketDataModel.sourceClose,
            ),
          ),
        );
      }
      if (usCloseCandidates.isNotEmpty) {
        final us = await _fetchWithRetry(
          () => _sinaApi.getQuotes(usCloseCandidates),
          attempts: 2,
        );
        closeByQuote.addAll(
          us.map(
            (e) => MarketDataModel(
              assetCode: e.assetCode,
              name: e.name,
              price: e.price,
              change: e.change,
              changePercent: e.changePercent,
              volume: e.volume,
              updatedAt: usLastClose,
              currency: e.currency,
              source: MarketDataModel.sourceClose,
            ),
          ),
        );
      }
      if (closeByQuote.isNotEmpty) {
        results.addAll(closeByQuote);
        fetchedCodeKeys.addAll(
          closeByQuote
              .expand((e) => _codeAliases(e.assetCode))
              .map(_normalizeCodeKey),
        );
        missingCodes =
            allRequestedCodes
                .where((c) => !fetchedCodeKeys.contains(_normalizeCodeKey(c)))
                .toSet();
        debugPrint(
          '[Market] close fallback(by quote api) recovered: ${closeByQuote.length}',
        );
      }
    }

    // 第三优先级：数据库缓存回退
    if (missingCodes.isNotEmpty) {
      try {
        final db = _ref.read(databaseProvider);
        final cached = await db.getAllMarketCache();
        final missingKeys = missingCodes.map(_normalizeCodeKey).toSet();
        for (final c in cached) {
          if (missingKeys.contains(_normalizeCodeKey(c.assetCode))) {
            results.add(
              MarketDataModel(
                assetCode: c.assetCode,
                name: c.name,
                price: c.price,
                change: c.change,
                changePercent: c.changePercent,
                volume: c.volume,
                updatedAt: _sanitizeQuoteTime(c.updatedAt),
                currency:
                    state[c.assetCode]?.currency ??
                    codeCurrencyHints[_normalizeCodeKey(c.assetCode)] ??
                    _inferCurrencyByCode(c.assetCode),
                source: MarketDataModel.sourceCache,
              ),
            );
          }
        }
        final recoveredKeys =
            results
                .expand((r) => _codeAliases(r.assetCode))
                .map(_normalizeCodeKey)
                .toSet();
        final stillMissing =
            missingCodes
                .where((c) => !recoveredKeys.contains(_normalizeCodeKey(c)))
                .toSet();
        debugPrint(
          '[Market] cache fallback: ${missingCodes.length} missing, recovered ${missingCodes.length - stillMissing.length}',
        );
        if (stillMissing.isNotEmpty) {
          debugPrint('[Market] still missing: $stillMissing');
        }
      } catch (e) {
        debugPrint('[Market] cache fallback error: $e');
      }
    }

    // 第四优先级：录入价回退（从未拉到行情 / 无可用接口）
    final recoveredKeysBeforeEntry =
        results
            .expand((r) => _codeAliases(r.assetCode))
            .map(_normalizeCodeKey)
            .toSet();
    final entryFallbackCodes =
        allRequestedCodes
            .where((c) => !recoveredKeysBeforeEntry.contains(_normalizeCodeKey(c)))
            .toSet();
    if (entryFallbackCodes.isNotEmpty) {
      for (final h in holdings) {
        final key = _normalizeCodeKey(h.assetCode);
        if (!entryFallbackCodes.contains(key) && !entryFallbackCodes.contains(h.assetCode)) {
          continue;
        }
        final entryPrice = h.initialPrice > 0 ? h.initialPrice : h.currentPrice;
        if (entryPrice <= 0) continue;
        results.add(
          MarketDataModel(
            assetCode: h.assetCode,
            name: h.assetName,
            price: entryPrice,
            change: entryPrice - h.costPrice,
            changePercent:
                h.costPrice > 0 ? ((entryPrice - h.costPrice) / h.costPrice) * 100 : 0,
            updatedAt: h.initialValuationDate,
            currency: h.currency.isEmpty ? 'CNY' : h.currency,
            source: MarketDataModel.sourceEntry,
          ),
        );
      }
    }

    // 更新状态
    final newState = Map<String, MarketDataModel>.from(state);
    for (final data in results) {
      for (final alias in _codeAliases(data.assetCode)) {
        newState[alias] = data;
      }
    }
    state = newState;

    // 仅将新获取的数据更新到缓存（不用缓存覆盖缓存）
    final freshResults =
        results.where((r) => fetchedCodes.contains(r.assetCode)).toList();
    _updateDbCache(freshResults);

    // 自动更新持仓表中的现价
    await _updateHoldingPrices(results);

    // 自动纠正分类：将 assetType 为 "other" 但分类器能识别的持仓重新分类
    await _reclassifyMistyped();

    // 价格更新后重新计算今日快照；若本次从接口拿到了最新行情，则强制覆盖今日点（不受 1% 阈值限制），并防抖上传 WebDAV（含 assetSnapshots，便于多设备看历史走势）
    try {
      final db = _ref.read(databaseProvider);
      final gotLiveQuotes = fetchedCodes.isNotEmpty;
      await SnapshotService(
        db,
      ).takeSnapshotIfNeeded(forceUpdateToday: gotLiveQuotes);
      if (gotLiveQuotes) {
        _ref.invalidate(snapshotListProvider);
        try {
          _ref.read(autoSyncProvider).triggerAutoSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<List<MarketDataModel>> _fetchSinglesForMissing({
    required Set<String> missingCodes,
    required Set<String> usCodes,
    required Set<String> fundCodes,
  }) async {
    final recovered = <MarketDataModel>[];
    for (final code in missingCodes) {
      try {
        MarketDataModel? one;
        if (usCodes.contains(code)) {
          one = await _sinaApi.getQuote(code);
          one ??= await _eastMoneyApi.getQuote(code);
        } else if (fundCodes.contains(code)) {
          one = await _fundApi.getQuote(code);
          one ??= await _eastMoneyApi.getQuote(code);
        } else {
          one = await _eastMoneyApi.getQuote(code);
        }
        if (one != null && one.price > 0) recovered.add(one);
      } catch (_) {}
    }
    return recovered;
  }

  /// 判断是否为交易所上市ETF（走股票行情接口而非基金净值接口）
  /// 上海: 510/511/512/513/515/516/518/520/560/561/562/563/588
  /// 深圳: 159xxx
  /// 排除 519xxx（LOF/开放式基金，走净值接口）
  static bool _isExchangeListedETF(String code) {
    final pure = code.replaceAll(
      RegExp(r'\.(SH|SZ|OF)$', caseSensitive: false),
      '',
    );
    if (!RegExp(r'^\d{6}$').hasMatch(pure)) return false;
    if (pure.startsWith('159')) return true;
    final prefix3 = pure.substring(0, 3);
    return const {
      '510',
      '511',
      '512',
      '513',
      '515',
      '516',
      '518',
      '520',
      '523',
      '560',
      '561',
      '562',
      '563',
      '588',
    }.contains(prefix3);
  }

  /// 将最新行情价格写入持仓表的 currentPrice 字段
  /// 包含异常检测：价格变化超过阈值时标注但不更新
  Future<void> _updateHoldingPrices(List<MarketDataModel> data) async {
    if (data.isEmpty) return;
    try {
      final db = _ref.read(databaseProvider);
      final holdings = _ref.read(allHoldingsProvider).valueOrNull ?? [];
      final priceMap = <String, double>{};
      for (final d in data) {
        for (final key in _codeAliases(d.assetCode)) {
          priceMap[key] = d.price;
        }
      }
      var updated = 0;
      var skipped = 0;

      for (final h in holdings) {
        final code = h.assetCode;
        double? newPrice;
        for (final key in _codeAliases(code)) {
          if (priceMap.containsKey(key)) {
            newPrice = priceMap[key];
            break;
          }
        }
        if (newPrice == null || newPrice <= 0 || newPrice == h.currentPrice) {
          continue;
        }

        // 异常检测 1: 持仓数量异常（负数或极大值）
        if (h.quantity < 0 || h.quantity > 1e9) {
          debugPrint(
            '[MarketData] ⚠️ 跳过异常持仓 "${h.assetName}"($code): 数量=${h.quantity}',
          );
          skipped++;
          continue;
        }

        // 异常检测 2: 价格变化幅度过大（单次超过 50% 视为可疑）
        if (h.currentPrice > 0) {
          final changePct =
              ((newPrice - h.currentPrice) / h.currentPrice).abs();
          if (changePct > 0.5) {
            final oldMv = h.quantity * h.currentPrice;
            final newMv = h.quantity * newPrice;
            debugPrint(
              '[MarketData] ⚠️ 价格变化异常 "${h.assetName}"($code): '
              '${h.currentPrice} → $newPrice (${(changePct * 100).toStringAsFixed(1)}%), '
              '市值 ${oldMv.toStringAsFixed(0)} → ${newMv.toStringAsFixed(0)}',
            );
            // 将异常信息记录到 notes，但仍然更新价格（行情 API 返回的通常是对的）
            final warning =
                '[行情异常 ${DateTime.now().toString().substring(0, 16)}] '
                '价格变化 ${(changePct * 100).toStringAsFixed(1)}%';
            final existingNotes = h.notes;
            final newNotes =
                existingNotes.contains('[行情异常')
                    ? existingNotes.replaceAll(
                      RegExp(r'\[行情异常[^\]]*\][^\n]*'),
                      warning,
                    )
                    : (existingNotes.isEmpty
                        ? warning
                        : '$existingNotes\n$warning');
            await db.updateHolding(
              HoldingsCompanion(
                id: Value(h.id),
                accountId: Value(h.accountId),
                assetCode: Value(h.assetCode),
                assetName: Value(h.assetName),
                assetType: Value(h.assetType),
                quantity: Value(h.quantity),
                costPrice: Value(h.costPrice),
                currentPrice: Value(newPrice),
                initialPrice: Value(h.initialPrice),
                initialValuationDate: Value(h.initialValuationDate),
                tags: Value(h.tags),
                notes: Value(newNotes),
                currency: Value(h.currency),
                createdAt: Value(h.createdAt),
                updatedAt: Value(DateTime.now()),
              ),
            );
            updated++;
            continue;
          }
        }

        await db.updateHolding(
          HoldingsCompanion(
            id: Value(h.id),
            accountId: Value(h.accountId),
            assetCode: Value(h.assetCode),
            assetName: Value(h.assetName),
            assetType: Value(h.assetType),
            quantity: Value(h.quantity),
            costPrice: Value(h.costPrice),
            currentPrice: Value(newPrice),
            initialPrice: Value(h.initialPrice),
            initialValuationDate: Value(h.initialValuationDate),
            tags: Value(h.tags),
            notes: Value(h.notes),
            currency: Value(h.currency),
            createdAt: Value(h.createdAt),
            updatedAt: Value(DateTime.now()),
          ),
        );
        updated++;
      }
      if (updated > 0 || skipped > 0) {
        debugPrint('[MarketData] 持仓现价更新: $updated 条更新, $skipped 条跳过');
      }
    } catch (e) {
      debugPrint('[MarketData] 更新持仓现价失败: $e');
    }
  }

  Future<List<MarketDataModel>> _fetchWithRetry(
    Future<List<MarketDataModel>> Function() fn, {
    int attempts = 2,
  }) async {
    Object? lastError;
    for (var i = 1; i <= attempts; i++) {
      try {
        return await fn();
      } catch (e) {
        lastError = e;
        if (i < attempts) {
          await Future.delayed(Duration(milliseconds: 400 * i));
        }
      }
    }
    throw lastError ?? Exception('fetch failed');
  }

  static String _normalizeCodeKey(String code) {
    final noSuffix = code.toUpperCase().replaceAll(
      RegExp(r'\.(US|HK|SH|SZ|OF|O|N)$'),
      '',
    );
    return noSuffix;
  }

  static DateTime _sanitizeQuoteTime(DateTime? dt) {
    if (dt == null) return DateTime.now();
    if (dt.year < 2000) return DateTime.now();
    return dt;
  }

  static bool _isCnTradingNow() {
    final now = _nowInUtc8();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }
    final m = now.hour * 60 + now.minute;
    return (m >= 9 * 60 + 30 && m < 11 * 60 + 30) ||
        (m >= 13 * 60 && m < 15 * 60);
  }

  static bool _isHkTradingNow() {
    final now = _nowInUtc8();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }
    final m = now.hour * 60 + now.minute;
    return (m >= 9 * 60 + 30 && m < 12 * 60) || (m >= 13 * 60 && m < 16 * 60);
  }

  static bool _isUsTradingNow() {
    final utcNow = DateTime.now().toUtc();
    if (utcNow.weekday == DateTime.saturday ||
        utcNow.weekday == DateTime.sunday) {
      return false;
    }
    final m = utcNow.hour * 60 + utcNow.minute;
    final isDst = _isUsDst(utcNow);
    if (isDst) {
      return m >= 13 * 60 + 30 && m < 20 * 60;
    }
    return m >= 14 * 60 + 30 && m < 21 * 60;
  }

  static DateTime _nowInUtc8() =>
      DateTime.now().toUtc().add(const Duration(hours: 8));

  static bool _isUsDst(DateTime utcNow) {
    final year = utcNow.year;
    final dstStart = _nthWeekdayOfMonthUtc(
      year: year,
      month: 3,
      weekday: DateTime.sunday,
      nth: 2,
      hourUtc: 7, // 2:00 EST == 07:00 UTC
    );
    final dstEnd = _nthWeekdayOfMonthUtc(
      year: year,
      month: 11,
      weekday: DateTime.sunday,
      nth: 1,
      hourUtc: 6, // 2:00 EDT == 06:00 UTC
    );
    return utcNow.isAfter(dstStart) && utcNow.isBefore(dstEnd);
  }

  static DateTime _nthWeekdayOfMonthUtc({
    required int year,
    required int month,
    required int weekday,
    required int nth,
    required int hourUtc,
  }) {
    var day = DateTime.utc(year, month, 1, hourUtc);
    while (day.weekday != weekday) {
      day = day.add(const Duration(days: 1));
    }
    day = day.add(Duration(days: (nth - 1) * 7));
    return day;
  }

  /// 计算最近已收盘交易日（A/HK 用 UTC+8；US 用 UTC-4/EDT）
  static DateTime _lastMarketCloseDay({required bool isUs}) {
    final DateTime ref;
    if (isUs) {
      // US EDT 近似 UTC-4（忽略夏冬令时偏差，仅影响边界 ±1 小时）
      ref = DateTime.now().toUtc().subtract(const Duration(hours: 4));
    } else {
      ref = _nowInUtc8();
    }
    final closeHour = isUs ? 16 : 15; // 16:00 EDT / 15:00 CST
    var d = DateTime(ref.year, ref.month, ref.day);
    if (ref.hour < closeHour) {
      d = d.subtract(const Duration(days: 1));
    }
    while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      d = d.subtract(const Duration(days: 1));
    }
    return DateTime(d.year, d.month, d.day, closeHour);
  }

  static Iterable<String> _codeAliases(String code) sync* {
    final raw = code.trim();
    if (raw.isEmpty) return;
    final upper = raw.toUpperCase();
    final normalized = _normalizeCodeKey(raw);
    yield raw;
    yield upper;
    yield normalized;
    if (RegExp(r'^\d{1,5}$').hasMatch(normalized)) {
      yield normalized.padLeft(5, '0');
      yield normalized.replaceFirst(RegExp(r'^0+'), '');
    }
  }

  static String _inferCurrencyByCode(String code) {
    final c = _normalizeCodeKey(code);
    if (RegExp(r'^[A-Z]{1,5}$').hasMatch(c)) return 'USD';
    if (RegExp(r'^\d{1,5}$').hasMatch(c)) return 'HKD';
    return 'CNY';
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
          await db.updateHolding(
            HoldingsCompanion(
              id: Value(h.id),
              accountId: Value(h.accountId),
              assetCode: Value(h.assetCode),
              assetName: Value(h.assetName),
              assetType: Value(newType),
              quantity: Value(h.quantity),
              costPrice: Value(h.costPrice),
              currentPrice: Value(h.currentPrice),
              initialPrice: Value(h.initialPrice),
              initialValuationDate: Value(h.initialValuationDate),
              tags: Value(h.tags),
              notes: Value(h.notes),
              currency: Value(h.currency),
              createdAt: Value(h.createdAt),
              updatedAt: Value(h.updatedAt),
            ),
          );
          fixed++;
          debugPrint(
            '[Market] reclassified "${h.assetName}": ${h.assetType} → $newType',
          );
        }
      }

      if (fullRescan) {
        await prefs.setInt('classifier_version', _classifierVersion);
      }
      debugPrint(
        '[Market] reclassify: scanned ${holdings.length}, fixed $fixed${fullRescan ? ' (full rescan v$_classifierVersion)' : ''}',
      );
    } catch (e) {
      debugPrint('[Market] reclassify error: $e');
    }
  }

  Future<void> _updateDbCache(List<MarketDataModel> data) async {
    final db = _ref.read(databaseProvider);
    final entries =
        data
            .map(
              (d) => MarketCacheCompanion(
                assetCode: Value(d.assetCode),
                price: Value(d.price),
                change: Value(d.change),
                changePercent: Value(d.changePercent),
                volume: Value(d.volume),
                name: Value(d.name),
                updatedAt: Value(d.updatedAt),
              ),
            )
            .toList();
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
