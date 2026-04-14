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
  final List<String> accountIds;

  const InstitutionGroup({
    required this.institution,
    required this.categories,
    required this.totalMarketValue,
    required this.holdingCount,
    this.accountIds = const [],
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

  // 按机构聚合持仓
  final instCatMap = <String, Map<CategoryGroup, List<HoldingSummary>>>{};
  // 按机构收集 accountId（包含空账户）
  final instAccountIds = <String, Set<String>>{};

  // 先把所有账户按机构注册（确保空账户也出现）
  for (final acc in accounts) {
    if (memberId != null && acc.memberId != memberId) continue;
    instAccountIds.putIfAbsent(acc.institution, () => {}).add(acc.id);
  }

  // 再聚合持仓
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

  // 构建结果：遍历所有机构（包含无持仓的）
  final groups = instAccountIds.entries.map((instEntry) {
    final institution = instEntry.key;
    final accountIds = instEntry.value.toList();
    final catMap = instCatMap[institution] ?? {};

    final catSubs = <CategorySubGroup>[];
    double instTotal = 0;
    int instCount = 0;

    for (final catEntry in catMap.entries) {
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
      institution: institution,
      categories: catSubs,
      totalMarketValue: instTotal,
      holdingCount: instCount,
      accountIds: accountIds,
    );
  }).toList()
    ..sort((a, b) => b.totalMarketValue.compareTo(a.totalMarketValue));

  return groups;
});
