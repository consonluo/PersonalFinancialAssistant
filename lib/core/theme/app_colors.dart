import 'package:flutter/material.dart';

/// 应用颜色常量
class AppColors {
  AppColors._();

  // ===== 主色调 =====
  static const Color primary = Color(0xFF3355CC);
  static const Color primaryDark = Color(0xFF2845A8);
  static const Color primaryMedium = Color(0xFF4A6FE0);
  static const Color primaryLight = Color(0xFF7B93F0);
  static const Color primarySurface = Color(0xFFE8EEFF);

  // ===== 背景色 =====
  static const Color backgroundLight = Color(0xFFF6F7FB);
  static const Color backgroundWhite = Color(0xFFFFFFFF);
  static const Color backgroundCard = Color(0xFFF0F2F8);
  static const Color backgroundDark = Color(0xFF0D1117);
  static const Color backgroundDarkCard = Color(0xFF161B22);

  // ===== 文字色 =====
  static const Color textPrimary = Color(0xFF1E2640);
  static const Color textSecondary = Color(0xFF5A6480);
  static const Color textHint = Color(0xFFAAB3C6);
  static const Color textOnPrimary = Colors.white;

  // ===== 功能色 =====
  static const Color loss = Color(0xFF2DA862);
  static const Color gain = Color(0xFFE5453E);
  static const Color warning = Color(0xFFE5A321);
  static const Color info = Color(0xFF3B8ADE);
  static const Color success = Color(0xFF2DA862);
  static const Color error = Color(0xFFE5453E);

  // ===== 渐变色 =====
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF3355CC), Color(0xFF4A6FE0), Color(0xFF7B93F0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF3355CC), Color(0xFF5A7AE8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient gainGradient = LinearGradient(
    colors: [Color(0xFFE5453E), Color(0xFFFF8A80)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient lossGradient = LinearGradient(
    colors: [Color(0xFF2DA862), Color(0xFF6FD89C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ===== 分类色板（更明亮） =====
  static const List<Color> categoryColors = [
    Color(0xFF3B6AE8), // 蓝
    Color(0xFFE5453E), // 红
    Color(0xFF2DA862), // 绿
    Color(0xFFE5A321), // 黄
    Color(0xFF7C5CE0), // 紫
    Color(0xFFEE7B30), // 橙
    Color(0xFF3EBFC2), // 青
    Color(0xFFD94B8A), // 玫红
    Color(0xFF5BA8F5), // 浅蓝
    Color(0xFF8CC152), // 黄绿
    Color(0xFFA38CD5), // 浅紫
    Color(0xFFE88D5A), // 浅橙
  ];

  static Color getCategoryColor(int index) {
    return categoryColors[index % categoryColors.length];
  }
}
