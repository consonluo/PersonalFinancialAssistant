import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/database_provider.dart';
import '../../providers/current_role_provider.dart';
import '../../providers/holding_provider.dart';
import '../../providers/account_provider.dart';
import '../../providers/family_provider.dart';
import '../../providers/liability_provider.dart';
import '../../providers/investment_plan_provider.dart';
import '../../providers/sync_provider.dart';
import '../../data/sync/data_serializer.dart';

class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key});

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  bool _checking = true;
  bool _loadingDemo = false;

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final familyId = prefs.getString('family_id');
    final roleId = prefs.getString('current_role_id');

    if (familyId != null && familyId.isNotEmpty) {
      final db = ref.read(databaseProvider);

      // Web 端 WASM 数据库初始化可能较慢，最多等 8 秒
      List members = [];
      for (int i = 0; i < 16; i++) {
        members = await db.getAllMembers();
        if (members.isNotEmpty) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 有 familyId 时，始终尝试从云端拉取最新数据（IndexedDB 是浏览器隔离的，
      // 不同设备/浏览器的本地数据可能不同步）
      if (familyId.isNotEmpty) {
        try {
          final sync = ref.read(autoSyncProvider);
          await sync.syncDown(familyId);
          members = await db.getAllMembers();
        } catch (_) {}
      }

      if (members.isNotEmpty) {
        ref.read(familyNameProvider.notifier).state =
            prefs.getString('family_name') ?? '我的家庭';
        ref.read(isDemoModeProvider.notifier).state = false;

        // 确保 familyIdProvider 内存状态与 SharedPreferences 一致
        // (它的异步 _load 可能还没完成)
        await ref.read(familyIdProvider.notifier).setFamilyId(familyId);
        await ref.read(syncConfigProvider.notifier).setFamilyId(familyId);

        if (roleId != null && members.any((m) => m.id == roleId)) {
          await ref.read(currentRoleProvider.notifier).setRole(roleId);
        } else {
          await ref.read(currentRoleProvider.notifier).setRole(members.first.id);
        }

        if (mounted) {
          context.go('/dashboard');
          return;
        }
      }
    }

    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(Icons.account_balance_wallet, size: 56, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  const Text('家庭资产管理', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('家庭资产，一目了然', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 16)),
                  const SizedBox(height: 60),
                  _ActionCard(icon: Icons.login_outlined, title: '登录已有家庭', subtitle: '用家庭账号或本地文件登录', onTap: () => context.push('/login-family')),
                  const SizedBox(height: 16),
                  _ActionCard(icon: Icons.add_home_outlined, title: '新建家庭', subtitle: '创建全新的家庭资产档案', onTap: () => context.push('/create-family')),
                  const SizedBox(height: 16),
                  _ActionCard(icon: Icons.explore_outlined, title: '游客体验', subtitle: _loadingDemo ? '正在加载演示数据...' : '使用演示数据体验完整功能', outlined: true, onTap: _loadingDemo ? () {} : () => _loadDemo(context)),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadDemo(BuildContext context) async {
    if (_loadingDemo) return;
    setState(() => _loadingDemo = true);

    try {
      final jsonStr = await rootBundle.loadString('assets/demo/demo_family.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final db = ref.read(databaseProvider);
      await DataSerializer(db).importAll(data);
      ref.read(familyNameProvider.notifier).state = data['familyName'] as String;
      ref.read(isDemoModeProvider.notifier).state = true;
      // 强制刷新数据源，防止残留旧数据
      ref.invalidate(allHoldingsProvider);
      ref.invalidate(allAccountsProvider);
      ref.invalidate(familyMembersProvider);
      ref.invalidate(allLiabilitiesProvider);
      ref.invalidate(allInvestmentPlansProvider);
      if (context.mounted) context.go('/role-select');
    } catch (e, stack) {
      debugPrint('游客体验加载失败: $e\n$stack');
      if (mounted) {
        setState(() => _loadingDemo = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载演示数据失败: $e'), duration: const Duration(seconds: 5)),
        );
      }
    }
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool outlined;

  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.onTap, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: outlined ? Colors.transparent : Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity, padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: outlined ? Border.all(color: Colors.white.withValues(alpha: 0.4)) : null),
          child: Row(
            children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: Colors.white, size: 28)),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
              ])),
              Icon(Icons.arrow_forward_ios, color: Colors.white.withValues(alpha: 0.5), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
