import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../providers/family_provider.dart';
import '../../../providers/asset_summary_provider.dart';

class MemberAssetBar extends ConsumerWidget {
  const MemberAssetBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(familyMembersProvider);

    return membersAsync.when(
      data: (members) {
        if (members.isEmpty) return const SizedBox.shrink();
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('成员资产分布',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                ...members.asMap().entries.map((e) {
                  final idx = e.key;
                  final member = e.value;
                  return _MemberRow(
                    name: member.name,
                    memberId: member.id,
                    color: AppColors.getCategoryColor(idx),
                  );
                }),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _MemberRow extends ConsumerWidget {
  final String name;
  final String memberId;
  final Color color;

  const _MemberRow({
    required this.name,
    required this.memberId,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myAssetValue = ref.watch(memberAssetProvider(memberId));
    final allMembers = ref.watch(familyMembersProvider).valueOrNull ?? [];

    double maxAsset = 0;
    for (final m in allMembers) {
      final v = ref.watch(memberAssetProvider(m.id));
      if (v > maxAsset) maxAsset = v;
    }

    final myAsset = myAssetValue;
    final ratio = maxAsset > 0 ? myAsset / maxAsset : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color.withValues(alpha: 0.2),
            child: Text(
              name.isNotEmpty ? name[0] : '?',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            child: Text(name,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 14,
                backgroundColor: AppColors.backgroundCard,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            FormatUtils.formatCurrency(myAsset),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
