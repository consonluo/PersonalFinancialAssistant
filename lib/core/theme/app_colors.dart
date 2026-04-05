import 'package:flutter/material.dart';

/// 应用颜色常量
class AppColors {
  AppColors._();

  // ===== 主色调 =====
  static const Color primary = Color(0xFF1A237E);
  static const Color primaryDark = Color(0xFF283593);
  static const Color primaryMedium = Color(0xFF3F51B5);
  static const Color primaryLight = Color(0xFF5C6BC0);
  static const Color primarySurface = Color(0xFFE8EAF6);

  // ===== 背景色 =====
  static const Color backgroundLight = Color(0xFFF5F7FA);
  static const Color backgroundWhite = Color(0xFFFFFFFF);
  static const Color backgroundCard = Color(0xFFEEF2F7);
  static const Color backgroundDark = Color(0xFF0D1117);
  static const Color backgroundDarkCard = Color(0xFF161B22);

  // ===== 文字色 =====
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF4A5568);
  static const Color textHint = Color(0xFFA0AEC0);
  static const Color textOnPrimary = Colors.white;

  // ===== 功能色 =====
  static const Color loss = Color(0xFF38A169); // 跌 - 绿色
  static const Color gain = Color(0xFFE53E3E); // 涨 - 红色
  static const Color warning = Color(0xFFD69E2E);
  static const Color info = Color(0xFF3182CE);
  static const Color success = Color(0xFF38A169);
  static const Color error = Color(0xFFE53E3E);

  // ===== 渐变色 =====
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF1A237E), Color(0xFF283593), Color(0xFF3F51B5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF1A237E), Color(0xFF5C6BC0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient gainGradient = LinearGradient(
    colors: [Color(0xFFE53E3E), Color(0xFFFC8181)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient lossGradient = LinearGradient(
    colors: [Color(0xFF38A169), Color(0xFF68D391)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ===== 分类色板 =====
  static const List<Color> categoryColors = [
    Color(0xFF1A237E), // 深蓝
    Color(0xFFE53E3E), // 红
    Color(0xFF38A169), // 绿
    Color(0xFFD69E2E), // 黄
    Color(0xFF3182CE), // 蓝
    Color(0xFF9F7AEA), // 紫
    Color(0xFFED8936), // 橙
    Color(0xFF4FD1C5), // 青
    Color(0xFFFC8181), // 浅红
    Color(0xFF63B3ED), // 浅蓝
    Color(0xFFA0AEC0), // 灰
    Color(0xFF805AD5), // 深紫
  ];

  static Color getCategoryColor(int index) {
    return categoryColors[index % categoryColors.length];
  }
}
