import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/category_group.dart';
import '../data/database/app_database.dart';
import 'account_provider.dart';
import 'holding_provider.dart';
import 'family_provider.dart';

/// 机构下按大分类聚合的数据
class InstitutionGroup {
  final String institution;
  final List<CategorySubGroup> categories;
  final double totalMarketValue;
  final int holdingCount;

  const InstitutionGroup({
    required this.institution,
    required this.categories,
    required this.totalMarketValue,
    required this.holdingCount,
  });
}

class CategorySubGroup {
  final CategoryGroup category;
  final List<HoldingSummary> holdings;
  final double totalMarketValue;

  const CategorySubGroup({
    required this.category,
    required this.holdings,
    required this.totalMarketValue,
  });
}

class HoldingSummary {
  final Holding holding;
  final String accountName;
  final String memberName;

  const HoldingSummary({
    required this.holding,
    required this.accountName,
    required this.memberName,
  });
}

/// 全量（不分成员）
final accountGroupProvider = Provider<List<InstitutionGroup>>((ref) {
  return ref.watch(accountGroupByMemberProvider(null));
});

/// 支持按成员筛选，null = 全部
final accountGroupByMemberProvider = Provider.family<List<InstitutionGroup>, String?>((ref, memberId) {
  final accounts = ref.watch(allAccountsProvider).valueOrNull ?? [];
  final allHoldings = ref.watch(allHoldingsProvider).valueOrNull ?? [];
  final members = ref.watch(familyMembersProvider).valueOrNull ?? [];

  final memberNameMap = {for (final m in members) m.id: m.name};
  final accountMap = {for (final a in accounts) a.id: a};

  final instCatMap = <String, Map<CategoryGroup, List<HoldingSummary>>>{};

  for (final h in allHoldings) {
    final acc = accountMap[h.accountId];
    if (acc == null) continue;
    if (memberId != null && acc.memberId != memberId) continue;
    final institution = acc.institution;
    final type = AssetType.values.where((e) => e.name == h.assetType).firstOrNull;
    final group = type != null ? getGroupForAssetType(type) : null;
    if (group == null) continue;

    instCatMap.putIfAbsent(institution, () => {});
    instCatMap[institution]!.putIfAbsent(group, () => []);
    instCatMap[institution]![group]!.add(HoldingSummary(
      holding: h,
      accountName: acc.name,
      memberName: memberNameMap[acc.memberId] ?? '',
    ));
  }

  final groups = instCatMap.entries.map((instEntry) {
    final catSubs = <CategorySubGroup>[];
    double instTotal = 0;
    int instCount = 0;

    for (final catEntry in instEntry.value.entries) {
      final catMv = catEntry.value.fold(0.0, (sum, hs) => sum + hs.holding.quantity * hs.holding.currentPrice);
      catSubs.add(CategorySubGroup(
        category: catEntry.key,
        holdings: catEntry.value,
        totalMarketValue: catMv,
      ));
      instTotal += catMv;
      instCount += catEntry.value.length;
    }
    catSubs.sort((a, b) => b.totalMarketValue.compareTo(a.totalMarketValue));

    return InstitutionGroup(
      institution: instEntry.key,
      categories: catSubs,
      totalMarketValue: instTotal,
      holdingCount: instCount,
    );
  }).toList()
    ..sort((a, b) => b.totalMarketValue.compareTo(a.totalMarketValue));

  return groups;
});
