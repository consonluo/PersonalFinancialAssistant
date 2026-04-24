import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_constants.dart';
import 'holding_provider.dart';
import 'market_provider.dart';

/// 市场分组定义
enum MarketGroup {
  aStock('A股市场'),
  hkStock('港股市场'),
  usStock('美股/海外'),
  bankWealth('银行/理财');

  const MarketGroup(this.label);
  final String label;
}

/// 根据 AssetType + 持仓名称判断所属市场
MarketGroup _resolveMarket(AssetType type, String name) {
  switch (type) {
    case AssetType.aStock:
      return MarketGroup.aStock;
    case AssetType.hkStock:
      return MarketGroup.hkStock;
    case AssetType.usStock:
      return MarketGroup.usStock;
    case AssetType.indexFund:
    case AssetType.activeFund:
      return _fundMarketByName(name);
    case AssetType.wealth:
    case AssetType.structuredDeposit:
    case AssetType.treasuryRepo:
    case AssetType.insurance:
    case AssetType.deposit:
    case AssetType.fixedDeposit:
    case AssetType.largeDeposit:
    case AssetType.noticeDeposit:
    case AssetType.moneyFund:
    case AssetType.bondFund:
    case AssetType.gold:
    case AssetType.realEstate:
    case AssetType.vehicle:
    case AssetType.other:
      return MarketGroup.bankWealth;
  }
}

/// 根据基金名称判断投资市场
MarketGroup _fundMarketByName(String name) {
  final n = name.toLowerCase();
  // 港股关键词
  if (n.contains('港股') || n.contains('恒生') || n.contains('香港') || n.contains('港股通')) {
    return MarketGroup.hkStock;
  }
  // 美股/海外关键词
  if (n.contains('纳指') || n.contains('纳斯达克') || n.contains('nasdaq') ||
      n.contains('标普') || n.contains('s&p') || n.contains('美国') || n.contains('美股') ||
      n.contains('qdii') || n.contains('海外') || n.contains('全球') || n.contains('国际')) {
    return MarketGroup.usStock;
  }
  return MarketGroup.aStock;
}

class MarketGroupData {
  final MarketGroup market;
  final double totalMarketValue;
  final double proportion;
  final int holdingCount;
  final List<HoldingDetail> holdings;

  const MarketGroupData({
    required this.market,
    required this.totalMarketValue,
    required this.proportion,
    required this.holdingCount,
    required this.holdings,
  });
}

class HoldingDetail {
  final String assetName;
  final String assetCode;
  final String assetType;
  final double quantity;
  final double costPrice;
  final double currentPrice;
  final double marketValue;
  final double pnl;
  final double pnlPercent;
  final double todayChangePercent;

  const HoldingDetail({
    required this.assetName,
    required this.assetCode,
    required this.assetType,
    required this.quantity,
    required this.costPrice,
    required this.currentPrice,
    required this.marketValue,
    required this.pnl,
    required this.pnlPercent,
    required this.todayChangePercent,
  });
}

class AssetAggregation {
  final String assetName;
  final String assetCode;
  final String assetType;
  final double totalQuantity;
  final double avgCostPrice;
  final double currentPrice;
  final double totalMarketValue;
  final double totalPnl;
  final double pnlPercent;

  const AssetAggregation({
    required this.assetName,
    required this.assetCode,
    required this.assetType,
    required this.totalQuantity,
    required this.avgCostPrice,
    required this.currentPrice,
    required this.totalMarketValue,
    required this.totalPnl,
    required this.pnlPercent,
  });
}

/// 按 AssetType 分组，组内再按 assetCode 聚合
class AssetTypeGroupData {
  final AssetType assetType;
  final double totalMarketValue;
  final double totalPnl;
  final double proportion;
  final int holdingCount;
  final List<AssetAggregation> items;

  const AssetTypeGroupData({
    required this.assetType,
    required this.totalMarketValue,
    required this.totalPnl,
    required this.proportion,
    required this.holdingCount,
    required this.items,
  });
}

/// 按市场分组的数据
final marketGroupProvider = Provider<List<MarketGroupData>>((ref) {
  final holdings = ref.watch(allHoldingsProvider).valueOrNull ?? [];
  final marketData = ref.watch(marketDataProvider);

  final map = <MarketGroup, List<HoldingDetail>>{};
  double grandTotal = 0;

  for (final h in holdings) {
    final type = AssetType.parse(h.assetType);
    final market = _resolveMarket(type, h.assetName);

    final mkt = marketData[h.assetCode];
    final price = mkt?.price ?? h.currentPrice;
    final mv = h.quantity * price;
    final pnl = (price - h.costPrice) * h.quantity;
    final pnlPct = h.costPrice != 0 ? (price - h.costPrice) / h.costPrice * 100 : 0.0;

    map.putIfAbsent(market, () => []).add(HoldingDetail(
      assetName: h.assetName,
      assetCode: h.assetCode,
      assetType: h.assetType,
      quantity: h.quantity,
      costPrice: h.costPrice,
      currentPrice: price,
      marketValue: mv,
      pnl: pnl,
      pnlPercent: pnlPct,
      todayChangePercent: mkt?.changePercent ?? 0.0,
    ));
    grandTotal += mv;
  }

  final result = <MarketGroupData>[];
  for (final m in MarketGroup.values) {
    final list = map[m];
    if (list == null || list.isEmpty) continue;
    final totalMv = list.fold(0.0, (sum, h) => sum + h.marketValue);
    result.add(MarketGroupData(
      market: m,
      totalMarketValue: totalMv,
      proportion: grandTotal > 0 ? totalMv / grandTotal * 100 : 0,
      holdingCount: list.length,
      holdings: list..sort((a, b) => b.marketValue.compareTo(a.marketValue)),
    ));
  }
  result.sort((a, b) => b.totalMarketValue.compareTo(a.totalMarketValue));
  return result;
});

/// 按品种聚合（同名资产跨账户合并）
final assetAggregationProvider = Provider<List<AssetAggregation>>((ref) {
  final holdings = ref.watch(allHoldingsProvider).valueOrNull ?? [];
  final marketData = ref.watch(marketDataProvider);

  final map = <String, _AggAcc>{};
  for (final h in holdings) {
    final mkt = marketData[h.assetCode];
    final price = mkt?.price ?? h.currentPrice;
    final key = h.assetCode.isNotEmpty ? h.assetCode : h.assetName;
    map.putIfAbsent(key, () => _AggAcc(name: h.assetName, code: h.assetCode, type: h.assetType, price: price));
    map[key]!.qty += h.quantity;
    map[key]!.totalCost += h.quantity * h.costPrice;
    map[key]!.price = price;
  }

  final result = map.values.map((a) {
    final mv = a.qty * a.price;
    final pnl = mv - a.totalCost;
    final avgCost = a.qty != 0 ? a.totalCost / a.qty : 0.0;
    return AssetAggregation(
      assetName: a.name,
      assetCode: a.code,
      assetType: a.type,
      totalQuantity: a.qty,
      avgCostPrice: avgCost,
      currentPrice: a.price,
      totalMarketValue: mv,
      totalPnl: pnl,
      pnlPercent: a.totalCost != 0 ? pnl / a.totalCost * 100 : 0,
    );
  }).toList()
    ..sort((a, b) => b.totalMarketValue.compareTo(a.totalMarketValue));

  return result;
});

/// 按 AssetType 分组的品种数据
final assetTypeGroupProvider = Provider<List<AssetTypeGroupData>>((ref) {
  final aggregations = ref.watch(assetAggregationProvider);
  if (aggregations.isEmpty) return [];

  double grandTotal = aggregations.fold(0.0, (s, a) => s + a.totalMarketValue);

  final typeMap = <String, List<AssetAggregation>>{};
  for (final a in aggregations) {
    typeMap.putIfAbsent(a.assetType, () => []).add(a);
  }

  final result = <AssetTypeGroupData>[];
  for (final entry in typeMap.entries) {
    final type = AssetType.parse(entry.key);
    final items = entry.value;
    final totalMv = items.fold(0.0, (s, a) => s + a.totalMarketValue);
    final totalPnl = items.fold(0.0, (s, a) => s + a.totalPnl);
    result.add(AssetTypeGroupData(
      assetType: type,
      totalMarketValue: totalMv,
      totalPnl: totalPnl,
      proportion: grandTotal > 0 ? totalMv / grandTotal * 100 : 0,
      holdingCount: items.length,
      items: items,
    ));
  }
  result.sort((a, b) => b.totalMarketValue.compareTo(a.totalMarketValue));
  return result;
});

class _AggAcc {
  String name, code, type;
  double qty = 0, totalCost = 0, price;
  _AggAcc({required this.name, required this.code, required this.type, required this.price});
}
