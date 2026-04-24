import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/category_group.dart';
import '../../providers/holding_provider.dart';
import '../../providers/market_provider.dart';
import '../../providers/asset_summary_provider.dart';
import '../../data/database/app_database.dart';
import '../../data/models/market_data_model.dart';
import '../../data/models/asset_summary_model.dart';

enum _SortMode { changeDesc, changeAsc, profitDesc, profitAsc }

class TodayChangePage extends ConsumerStatefulWidget {
  const TodayChangePage({super.key});

  @override
  ConsumerState<TodayChangePage> createState() => _TodayChangePageState();
}

class _TodayChangePageState extends ConsumerState<TodayChangePage> {
  _SortMode _sortMode = _SortMode.changeDesc;

  @override
  Widget build(BuildContext context) {
    final holdingsAsync = ref.watch(allHoldingsProvider);
    final marketData = ref.watch(marketDataProvider);
    final overview = ref.watch(assetSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('今日涨跌'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.sort, size: 22),
            tooltip: '排序',
            onSelected: (mode) => setState(() => _sortMode = mode),
            itemBuilder: (_) => [
              _sortItem(_SortMode.changeDesc, '涨跌幅 高→低'),
              _sortItem(_SortMode.changeAsc, '涨跌幅 低→高'),
              _sortItem(_SortMode.profitDesc, '收益额 高→低'),
              _sortItem(_SortMode.profitAsc, '收益额 低→高'),
            ],
          ),
        ],
      ),
      body: holdingsAsync.when(
        data: (holdings) {
          final items = _buildItems(holdings, marketData);
          if (items.isEmpty) {
            return const Center(child: Text('暂无持仓数据', style: TextStyle(color: AppColors.textSecondary)));
          }
          return CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _SummaryHeader(overview: overview)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _HoldingTile(item: items[i]),
                  childCount: items.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }

  PopupMenuItem<_SortMode> _sortItem(_SortMode mode, String label) {
    return PopupMenuItem(
      value: mode,
      child: Row(children: [
        if (_sortMode == mode) const Icon(Icons.check, size: 18, color: AppColors.primary) else const SizedBox(width: 18),
        const SizedBox(width: 8),
        Text(label),
      ]),
    );
  }

  List<_HoldingItem> _buildItems(List<Holding> holdings, Map<String, MarketDataModel> marketData) {
    final items = <_HoldingItem>[];
    for (final h in holdings) {
      if (h.quantity == 0) continue;
      final market = marketData[h.assetCode];
      final currentPrice = market?.price ?? h.currentPrice;
      final mv = h.quantity * currentPrice;
      final cost = h.quantity * h.costPrice;
      final totalProfit = mv - cost;
      final totalProfitPct = h.costPrice > 0 ? (currentPrice - h.costPrice) / h.costPrice * 100 : 0.0;
      final todayChangePct = market?.changePercent ?? 0.0;
      final todayChange = market != null ? mv * todayChangePct / 100 : 0.0;
      final type = AssetType.values.firstWhere((e) => e.name == h.assetType, orElse: () => AssetType.other);

      items.add(_HoldingItem(
        name: h.assetName,
        code: h.assetCode,
        assetType: type,
        marketValue: mv,
        todayChange: todayChange,
        todayChangePct: todayChangePct,
        totalProfit: totalProfit,
        totalProfitPct: totalProfitPct,
        hasMarketData: market != null,
        updatedAt: market?.updatedAt,
      ));
    }

    switch (_sortMode) {
      case _SortMode.changeDesc:
        items.sort((a, b) => b.todayChangePct.compareTo(a.todayChangePct));
      case _SortMode.changeAsc:
        items.sort((a, b) => a.todayChangePct.compareTo(b.todayChangePct));
      case _SortMode.profitDesc:
        items.sort((a, b) => b.todayChange.compareTo(a.todayChange));
      case _SortMode.profitAsc:
        items.sort((a, b) => a.todayChange.compareTo(b.todayChange));
    }
    return items;
  }
}

class _HoldingItem {
  final String name;
  final String code;
  final AssetType assetType;
  final double marketValue;
  final double todayChange;
  final double todayChangePct;
  final double totalProfit;
  final double totalProfitPct;
  final bool hasMarketData;
  final DateTime? updatedAt;

  const _HoldingItem({
    required this.name,
    required this.code,
    required this.assetType,
    required this.marketValue,
    required this.todayChange,
    required this.todayChangePct,
    required this.totalProfit,
    required this.totalProfitPct,
    required this.hasMarketData,
    this.updatedAt,
  });
}

class _SummaryHeader extends StatelessWidget {
  final FamilyAssetOverview overview;
  const _SummaryHeader({required this.overview});

  @override
  Widget build(BuildContext context) {
    final isUp = overview.todayChange >= 0;
    final color = isUp ? AppColors.gain : AppColors.loss;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isUp ? AppColors.gainGradient : AppColors.lossGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Text('今日总收益', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            FormatUtils.formatChange(overview.todayChange),
            style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            FormatUtils.formatPercent(overview.todayChangePercent),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _miniStat('总资产', FormatUtils.formatCurrency(overview.totalAssets)),
              Container(width: 1, height: 24, color: Colors.white.withValues(alpha: 0.3)),
              _miniStat('持仓数', '${overview.categories.fold(0, (s, c) => s + c.holdingCount)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(children: [
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _HoldingTile extends StatelessWidget {
  final _HoldingItem item;
  const _HoldingTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final group = getGroupForAssetType(item.assetType);
    final groupColor = group?.color ?? AppColors.textSecondary;
    final changeColor = item.todayChangePct > 0
        ? AppColors.gain
        : item.todayChangePct < 0
            ? AppColors.loss
            : AppColors.textSecondary;
    final profitColor = item.totalProfit > 0
        ? AppColors.gain
        : item.totalProfit < 0
            ? AppColors.loss
            : AppColors.textSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.backgroundCard),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: groupColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Text(
                  item.assetType.code,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: groupColor),
                )),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      '${item.assetType.label} · ${item.code}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    FormatUtils.formatPercent(item.todayChangePct),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: changeColor),
                  ),
                  Text(
                    FormatUtils.formatChange(item.todayChange),
                    style: TextStyle(fontSize: 12, color: changeColor),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.backgroundLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _statCol('市值', FormatUtils.formatCurrency(item.marketValue), AppColors.textPrimary),
                _statCol('总收益', FormatUtils.formatChange(item.totalProfit), profitColor),
                _statCol('总收益率', FormatUtils.formatPercent(item.totalProfitPct), profitColor),
                if (!item.hasMarketData)
                  Expanded(child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(Icons.cloud_off, size: 12, color: AppColors.textHint),
                      const SizedBox(width: 2),
                      Text('无行情', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
                    ],
                  ))
                else if (item.updatedAt != null)
                  Expanded(child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _formatDataTime(item.updatedAt!),
                      style: const TextStyle(fontSize: 10, color: AppColors.textHint),
                    ),
                  )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCol(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          const SizedBox(height: 1),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: valueColor), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  String _formatDataTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dataDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(dataDay).inDays;

    if (diff == 0) {
      // 今天的数据：交易时间内显示"实时"，收盘后显示"今日 HH:mm"
      if (dt.hour >= 9 && dt.hour < 15 && now.hour >= 9 && now.hour < 16) {
        return '实时';
      }
      return '今日 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff == 1) return '昨日';
    if (diff == 2 && dataDay.weekday == DateTime.friday) return '上周五';
    if (diff == 3 && dataDay.weekday == DateTime.friday) return '上周五';
    if (diff <= 7) return '$diff天前';
    return '${dt.month}/${dt.day}';
  }
}
