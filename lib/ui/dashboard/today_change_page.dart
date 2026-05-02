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
            itemBuilder:
                (_) => [
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
            return const Center(
              child: Text(
                '暂无持仓数据',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }
          return CustomScrollView(
            slivers: [
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
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }

  PopupMenuItem<_SortMode> _sortItem(_SortMode mode, String label) {
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          if (_sortMode == mode)
            const Icon(Icons.check, size: 18, color: AppColors.primary)
          else
            const SizedBox(width: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  List<_HoldingItem> _buildItems(
    List<Holding> holdings,
    Map<String, MarketDataModel> marketData,
  ) {
    final items = <_HoldingItem>[];
    for (final h in holdings) {
      if (h.quantity == 0) continue;
      final market = marketData[h.assetCode];
      final entryPrice = h.initialPrice > 0 ? h.initialPrice : h.currentPrice;
      final effectiveMarket =
          market ??
          (entryPrice > 0
              ? MarketDataModel(
                assetCode: h.assetCode,
                name: h.assetName,
                price: entryPrice,
                change: entryPrice - h.costPrice,
                changePercent:
                    h.costPrice > 0
                        ? ((entryPrice - h.costPrice) / h.costPrice) * 100
                        : 0,
                updatedAt: h.initialValuationDate,
                currency: h.currency.isEmpty ? 'CNY' : h.currency,
                source: MarketDataModel.sourceEntry,
              )
              : null);
      final currentPrice = effectiveMarket?.price ?? h.currentPrice;
      final mv = h.quantity * currentPrice;
      final cost = h.quantity * h.costPrice;
      final totalProfit = mv - cost;
      final totalProfitPct =
          h.costPrice > 0
              ? (currentPrice - h.costPrice) / h.costPrice * 100
              : 0.0;
      final todayChangePct = effectiveMarket?.changePercent ?? 0.0;
      final todayChange =
          effectiveMarket != null ? mv * todayChangePct / 100 : 0.0;
      final type = AssetType.values.firstWhere(
        (e) => e.name == h.assetType,
        orElse: () => AssetType.other,
      );

      items.add(
        _HoldingItem(
          name: h.assetName,
          code: h.assetCode,
          assetType: type,
          marketValue: mv,
          todayChange: todayChange,
          todayChangePct: todayChangePct,
          totalProfit: totalProfit,
          totalProfitPct: totalProfitPct,
          hasMarketData: effectiveMarket != null,
          currentPrice: effectiveMarket?.price,
          costPrice: h.costPrice,
          currency:
              (effectiveMarket?.currency.isNotEmpty == true)
                  ? effectiveMarket!.currency
                  : (h.currency.isEmpty ? 'CNY' : h.currency),
          updatedAt: effectiveMarket?.updatedAt,
          quoteSource: effectiveMarket?.source,
        ),
      );
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
  final double? currentPrice;
  final double costPrice;
  final String currency;
  final DateTime? updatedAt;
  final String? quoteSource;

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
    this.currentPrice,
    this.costPrice = 0,
    this.currency = 'CNY',
    this.updatedAt,
    this.quoteSource,
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
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            '今日总收益',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            FormatUtils.formatChange(overview.todayChange),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            FormatUtils.formatPercent(overview.todayChangePercent),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _miniStat(
                '总资产',
                FormatUtils.formatCurrency(overview.totalAssets),
              ),
              Container(
                width: 1,
                height: 24,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              _miniStat(
                '持仓数',
                '${overview.categories.fold(0, (s, c) => s + c.holdingCount)}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _HoldingTile extends StatelessWidget {
  final _HoldingItem item;
  const _HoldingTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final group = getGroupForAssetType(item.assetType);
    final groupColor = group?.color ?? AppColors.textSecondary;
    final changeColor =
        item.todayChangePct > 0
            ? AppColors.gain
            : item.todayChangePct < 0
            ? AppColors.loss
            : AppColors.textSecondary;
    final profitColor =
        item.totalProfit > 0
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: groupColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    item.assetType.code,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: groupColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.assetType.label} · ${item.code}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (item.hasMarketData &&
                        item.currentPrice != null &&
                        item.currentPrice! > 0) ...[
                      Text(
                        FormatUtils.formatPrice(
                          item.currentPrice!,
                          currency: item.currency,
                        ),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.end,
                      ),
                      if (item.costPrice > 0)
                        Text(
                          '成本 ${FormatUtils.formatPrice(item.costPrice, currency: item.currency)}',
                          style: const TextStyle(
                            fontSize: 9,
                            color: AppColors.textHint,
                          ),
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                    Text(
                      item.hasMarketData
                          ? FormatUtils.formatPercent(item.todayChangePct)
                          : '--',
                      style: TextStyle(
                        fontSize:
                            item.hasMarketData && item.currentPrice != null
                                ? 13
                                : 16,
                        fontWeight: FontWeight.w700,
                        color: changeColor,
                      ),
                      textAlign: TextAlign.end,
                    ),
                    Text(
                      item.hasMarketData
                          ? FormatUtils.formatChange(
                            item.todayChange,
                            currency: item.currency,
                          )
                          : '--',
                      style: TextStyle(fontSize: 11, color: changeColor),
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
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
                _statCol(
                  '市值',
                  FormatUtils.formatCurrency(
                    item.marketValue,
                    currency: item.currency,
                  ),
                  AppColors.textPrimary,
                ),
                _statCol(
                  '总收益',
                  FormatUtils.formatChange(
                    item.totalProfit,
                    currency: item.currency,
                  ),
                  profitColor,
                ),
                _statCol(
                  '总收益率',
                  FormatUtils.formatPercent(item.totalProfitPct),
                  profitColor,
                ),
                if (!item.hasMarketData)
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(
                          Icons.cloud_off,
                          size: 12,
                          color: AppColors.textHint,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '未拉到行情',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (item.updatedAt != null)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_sourceLabel(item.quoteSource) != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.backgroundCard,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _sourceLabel(item.quoteSource)!,
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            _formatDataTime(item.updatedAt!, item.quoteSource),
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _formatDataTime(DateTime dt, String? source) {
    if (dt.year < 2000) return '未知';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dataDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(dataDay).inDays;

    if (source == MarketDataModel.sourceCache) {
      return '缓存 ${dt.month}/${dt.day}';
    }
    if (source == MarketDataModel.sourceClose) {
      if (diff == 0) return '今日收盘';
      if (diff == 1) return '昨日收盘';
      return '收盘 ${dt.month}/${dt.day}';
    }
    if (source == MarketDataModel.sourceEntry) {
      return '录入 ${dt.month}/${dt.day}';
    }

    // diff < 0 表示数据日期是未来（API 时间戳异常），直接显示日期
    if (diff < 0) return '${dt.month}/${dt.day}';

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

  String? _sourceLabel(String? source) {
    switch (source) {
      case MarketDataModel.sourceLive:
        return null;
      case MarketDataModel.sourceClose:
        return '收盘价';
      case MarketDataModel.sourceCache:
        return '缓存价';
      case MarketDataModel.sourceEntry:
        return '录入价';
      default:
        return null;
    }
  }
}
