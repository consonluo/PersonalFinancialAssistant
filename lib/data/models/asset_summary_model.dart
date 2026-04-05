import '../../core/constants/app_constants.dart';

/// 资产汇总模型 - 按分类聚合
class AssetSummaryModel {
  final AssetType assetType;
  final String categoryName;
  final double totalMarketValue;
  final double totalCost;
  final double profitLoss;
  final double profitLossPercent;
  final double proportion; // 占总资产比例 0~100
  final int holdingCount;
  final double todayChange;

  const AssetSummaryModel({
    required this.assetType,
    required this.categoryName,
    this.totalMarketValue = 0,
    this.totalCost = 0,
    this.profitLoss = 0,
    this.profitLossPercent = 0,
    this.proportion = 0,
    this.holdingCount = 0,
    this.todayChange = 0,
  });
}

/// 家庭总资产概览
class FamilyAssetOverview {
  final double totalAssets; // 总资产（投资+固定+现金）
  final double totalInvestment; // 投资资产
  final double totalFixedAssets; // 固定资产
  final double totalLiabilities; // 总负债
  final double netWorth; // 净资产
  final double todayChange; // 今日涨跌
  final double todayChangePercent; // 今日涨跌%
  final List<AssetSummaryModel> categories; // 分类汇总

  const FamilyAssetOverview({
    this.totalAssets = 0,
    this.totalInvestment = 0,
    this.totalFixedAssets = 0,
    this.totalLiabilities = 0,
    this.netWorth = 0,
    this.todayChange = 0,
    this.todayChangePercent = 0,
    this.categories = const [],
  });
}
