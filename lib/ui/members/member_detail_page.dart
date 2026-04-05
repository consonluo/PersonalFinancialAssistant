import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/family_provider.dart';
import '../../providers/account_provider.dart';

class MemberDetailPage extends ConsumerWidget {
  final String memberId;
  const MemberDetailPage({super.key, required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(memberByIdProvider(memberId));
    final accountsAsync = ref.watch(accountsByMemberProvider(memberId));

    return Scaffold(
      appBar: AppBar(
        title: memberAsync.whenOrNull(data: (m) => Text(m?.name ?? '')) ?? const Text('成员详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => context.push('/member-form?id=$memberId'),
          ),
        ],
      ),
      body: accountsAsync.when(
        data: (accounts) {
          if (accounts.isEmpty) {
            return const Center(child: Text('暂无账户，点击右下角添加'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: accounts.length,
            itemBuilder: (context, index) {
              final acc = accounts[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Icon(
                    acc.type == 'securities' ? Icons.trending_up : Icons.account_balance,
                    color: AppColors.primary,
                  ),
                  title: Text(acc.name),
                  subtitle: Text('${acc.institution} · ${acc.type == "securities" ? "证券" : "银行"}'),
                  trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
                  onTap: () => context.push('/holdings?accountId=${acc.id}'),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/account-form?memberId=$memberId'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
