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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('成员资产分布', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: members.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final member = members[index];
                  return _MemberChip(
                    name: member.name,
                    memberId: member.id,
                    color: AppColors.getCategoryColor(index),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _MemberChip extends ConsumerWidget {
  final String name;
  final String memberId;
  final Color color;

  const _MemberChip({
    required this.name,
    required this.memberId,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetAsync = ref.watch(memberAssetProvider(memberId));

    return Container(
      width: 110,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: 0.2),
            child: Text(
              name.isNotEmpty ? name[0] : '?',
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          const SizedBox(height: 6),
          Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          assetAsync.when(
            data: (total) => Text(
              FormatUtils.formatCurrency(total),
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
            loading: () => const Text('...', style: TextStyle(fontSize: 11)),
            error: (_, _) => const Text('-', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
