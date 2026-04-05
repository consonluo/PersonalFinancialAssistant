import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format_utils.dart';
import '../../providers/family_provider.dart';
import '../../providers/account_provider.dart';
import '../../providers/asset_summary_provider.dart';

class MemberListPage extends ConsumerWidget {
  const MemberListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(familyMembersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('家庭成员')),
      body: membersAsync.when(
        data: (members) {
          if (members.isEmpty) {
            return const Center(child: Text('暂无成员，请先添加'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: members.length,
            itemBuilder: (context, index) {
              final m = members[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () => context.go('/members/${m.id}'),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.getCategoryColor(index),
                          child: Text(m.name[0], style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              Text(m.role, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            ],
                          ),
                        ),
                        Consumer(builder: (_, ref, __) {
                          final asset = ref.watch(memberAssetProvider(m.id));
                          return asset.when(
                            data: (v) => Text(FormatUtils.formatCurrency(v), style: const TextStyle(fontWeight: FontWeight.w600)),
                            loading: () => const Text('...'),
                            error: (_, __) => const Text('-'),
                          );
                        }),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, color: AppColors.textHint),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/member-form'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
