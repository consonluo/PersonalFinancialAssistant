import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

class FamilyFinanceApp extends StatelessWidget {
  const FamilyFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '加财',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      routerConfig: appRouter,
      builder: (context, child) {
        // iOS Web 上 Safari 左滑返回会触发双重 pop，用 PopScope 防抖
        if (kIsWeb) {
          return _WebPopDebounce(child: child ?? const SizedBox());
        }
        return child ?? const SizedBox();
      },
    );
  }
}

/// Web 端全局返回防抖：防止 iOS Safari 左滑返回触发双重导航
class _WebPopDebounce extends StatefulWidget {
  final Widget child;
  const _WebPopDebounce({required this.child});

  @override
  State<_WebPopDebounce> createState() => _WebPopDebounceState();
}

class _WebPopDebounceState extends State<_WebPopDebounce> {
  DateTime _lastPopTime = DateTime(2000);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        if (now.difference(_lastPopTime).inMilliseconds < 800) {
          return; // 800ms 内的重复 pop 忽略
        }
        _lastPopTime = now;
        // 手动执行一次 pop
        if (appRouter.canPop()) {
          appRouter.pop();
        }
      },
      child: widget.child,
    );
  }
}
