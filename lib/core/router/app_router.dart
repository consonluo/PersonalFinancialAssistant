import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../ui/welcome/welcome_page.dart';
import '../../ui/welcome/create_family_page.dart';
import '../../ui/welcome/login_family_page.dart';
import '../../ui/welcome/role_select_page.dart';
import '../../ui/dashboard/dashboard_page.dart';
import '../../ui/members/member_detail_page.dart';
import '../../ui/members/member_form_page.dart';
import '../../ui/accounts/account_list_page.dart';
import '../../ui/accounts/account_detail_page.dart';
import '../../ui/accounts/account_form_page.dart';
import '../../ui/holdings/holding_list_page.dart';
import '../../ui/holdings/holding_form_page.dart';
import '../../ui/holdings/ocr_import_page.dart';
import '../../ui/analysis/analysis_page.dart';
import '../../ui/analysis/category_detail_page.dart';
import '../../ui/analysis/category_group_detail_page.dart';
import '../../ui/analysis/asset_trend_page.dart';
import '../../ui/liabilities/liability_list_page.dart';
import '../../ui/liabilities/liability_form_page.dart';
import '../../ui/liabilities/balance_sheet_page.dart';
import '../../ui/fixed_assets/fixed_asset_list_page.dart';
import '../../ui/fixed_assets/fixed_asset_form_page.dart';
import '../../ui/investment/investment_plan_list_page.dart';
import '../../ui/investment/investment_plan_form_page.dart';
import '../../ui/investment/investment_plan_ocr_page.dart';
import '../../ui/liabilities/liability_ocr_page.dart';
import '../../ui/settings/settings_page.dart';
import '../../ui/settings/data_manage_page.dart';

import '../../ui/analysis/ai_analysis_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// 应用路由配置
final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/welcome',
  routes: [
    // 欢迎引导流程
    GoRoute(path: '/welcome', builder: (context, state) => const WelcomePage()),
    GoRoute(path: '/create-family', builder: (context, state) => const CreateFamilyPage()),
    GoRoute(path: '/login-family', builder: (context, state) => const LoginFamilyPage()),
    GoRoute(path: '/role-select', builder: (context, state) => const RoleSelectPage()),

    // 主界面 Shell 路由（带底部导航栏，4个 Tab：首页、账户、分析、设置）
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(path: '/dashboard', builder: (context, state) => const DashboardPage()),
        GoRoute(
          path: '/accounts',
          builder: (context, state) => const AccountListPage(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) => AccountDetailPage(accountId: state.pathParameters['id']!),
            ),
          ],
        ),
        GoRoute(
          path: '/analysis',
          builder: (context, state) => const AnalysisPage(),
          routes: [
            GoRoute(
              path: 'category/:type',
              builder: (context, state) => CategoryDetailPage(categoryType: state.pathParameters['type']!),
            ),
            GoRoute(
              path: 'category-group/:group',
              builder: (context, state) => CategoryGroupDetailPage(groupName: state.pathParameters['group']!),
            ),
          ],
        ),
        GoRoute(path: '/settings', builder: (context, state) => const SettingsPage()),
      ],
    ),

    // 独立页面（不含底部导航栏）
    GoRoute(
      path: '/member-form',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => MemberFormPage(memberId: state.uri.queryParameters['id']),
    ),
    GoRoute(
      path: '/members/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => MemberDetailPage(memberId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/account-form',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => AccountFormPage(
        accountId: state.uri.queryParameters['id'],
        memberId: state.uri.queryParameters['memberId'],
      ),
    ),
    GoRoute(
      path: '/holding-form',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => HoldingFormPage(
        holdingId: state.uri.queryParameters['id'],
        accountId: state.uri.queryParameters['accountId'],
      ),
    ),
    GoRoute(
      path: '/holdings',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => HoldingListPage(accountId: state.uri.queryParameters['accountId']!),
    ),
    GoRoute(
      path: '/ocr-import',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => OcrImportPage(accountId: state.uri.queryParameters['accountId']!),
    ),
    GoRoute(
      path: '/ai-analysis',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final extra = state.extra;
        if (extra is Map<String, dynamic>) {
          return AiAnalysisPage(
            title: state.uri.queryParameters['title'] ?? 'AI 分析',
            streamParams: extra,
          );
        }
        return AiAnalysisPage(
          title: state.uri.queryParameters['title'] ?? 'AI 分析',
          content: extra as String? ?? '',
        );
      },
    ),
    GoRoute(
      path: '/liabilities',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const LiabilityListPage(),
    ),
    GoRoute(
      path: '/liability-form',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => LiabilityFormPage(
        liabilityId: state.uri.queryParameters['id'],
        memberId: state.uri.queryParameters['memberId'],
      ),
    ),
    GoRoute(
      path: '/balance-sheet',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const BalanceSheetPage(),
    ),
    GoRoute(
      path: '/data-manage',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const DataManagePage(),
    ),
    GoRoute(
      path: '/fixed-assets',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const FixedAssetListPage(),
    ),
    GoRoute(
      path: '/fixed-asset-form',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => FixedAssetFormPage(
        assetId: state.uri.queryParameters['id'],
        memberId: state.uri.queryParameters['memberId'],
      ),
    ),
    GoRoute(
      path: '/asset-trend',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AssetTrendPage(),
    ),
    GoRoute(
      path: '/investment-plans',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const InvestmentPlanListPage(),
    ),
    GoRoute(
      path: '/investment-plan-form',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => InvestmentPlanFormPage(
        planId: state.uri.queryParameters['id'],
      ),
    ),
    GoRoute(
      path: '/investment-plan-ocr',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const InvestmentPlanOcrPage(),
    ),
    GoRoute(
      path: '/liability-ocr',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => LiabilityOcrPage(
        memberId: state.uri.queryParameters['memberId'],
      ),
    ),
  ],
);

/// 主界面外壳（4 Tab：首页、账户、分析、设置）
/// 宽屏 (>=800) 使用左侧 NavigationRail，窄屏使用底部 NavigationBar
class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _paths = ['/dashboard', '/accounts', '/analysis', '/settings'];

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/dashboard')) return 0;
    if (location.startsWith('/accounts')) return 1;
    if (location.startsWith('/analysis')) return 2;
    if (location.startsWith('/settings')) return 3;
    return 0;
  }

  void _onSelect(BuildContext context, int index) {
    context.go(_paths[index]);
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;

        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (i) => _onSelect(context, i),
                  labelType: NavigationRailLabelType.all,
                  leading: const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 16),
                    child: Icon(Icons.account_balance_wallet, size: 28),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: Text('总览'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.account_balance_outlined),
                      selectedIcon: Icon(Icons.account_balance),
                      label: Text('账户'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.analytics_outlined),
                      selectedIcon: Icon(Icons.analytics),
                      label: Text('分析'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('设置'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: child),
              ],
            ),
          );
        }

        return Scaffold(
          body: child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: (i) => _onSelect(context, i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: '总览',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_outlined),
                selectedIcon: Icon(Icons.account_balance),
                label: '账户',
              ),
              NavigationDestination(
                icon: Icon(Icons.analytics_outlined),
                selectedIcon: Icon(Icons.analytics),
                label: '分析',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        );
      },
    );
  }
}
