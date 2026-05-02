import 'package:intl/intl.dart';

/// 格式化工具类
class FormatUtils {
  FormatUtils._();

  static final _currencyFormat = NumberFormat('#,##0.00');
  static final _intFormat = NumberFormat('#,##0');
  static final _percentFormat = NumberFormat('0.00');
  static final _dateFormat = DateFormat('yyyy-MM-dd');
  static final _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');

  /// 各币种符号映射
  static const Map<String, String> currencySymbols = {
    'CNY': '¥',
    'USD': r'$',
    'HKD': r'HK$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
    'SGD': r'S$',
    'TWD': r'NT$',
    'AUD': r'A$',
    'CAD': r'C$',
  };

  /// 根据币种代码获取符号；空或未知时返回 ¥
  static String currencySymbol(String? currency) {
    if (currency == null || currency.isEmpty) return '¥';
    return currencySymbols[currency.toUpperCase()] ?? currency.toUpperCase();
  }

  /// 格式化金额（带千分位）
  /// [currency] 优先于 [prefix]：传了 currency 时按对应币种符号显示。
  static String formatCurrency(
    double amount, {
    String prefix = '¥',
    String? currency,
  }) {
    final p = currency != null ? currencySymbol(currency) : prefix;
    if (amount.abs() >= 100000000) {
      return '$p${_percentFormat.format(amount / 100000000)}亿';
    }
    if (amount.abs() >= 10000) {
      return '$p${_percentFormat.format(amount / 10000)}万';
    }
    return '$p${_currencyFormat.format(amount)}';
  }

  /// 格式化完整金额（不缩略）
  static String formatFullCurrency(
    double amount, {
    String prefix = '¥',
    String? currency,
  }) {
    final p = currency != null ? currencySymbol(currency) : prefix;
    return '$p${_currencyFormat.format(amount)}';
  }

  /// 格式化整数金额
  static String formatIntCurrency(
    double amount, {
    String prefix = '¥',
    String? currency,
  }) {
    final p = currency != null ? currencySymbol(currency) : prefix;
    return '$p${_intFormat.format(amount)}';
  }

  /// 格式化百分比
  static String formatPercent(double value) {
    final sign = value >= 0 ? '+' : '';
    return '$sign${_percentFormat.format(value)}%';
  }

  /// 格式化涨跌额
  static String formatChange(
    double value, {
    String prefix = '¥',
    String? currency,
  }) {
    final p = currency != null ? currencySymbol(currency) : prefix;
    final sign = value >= 0 ? '+' : '';
    return '$sign$p${_currencyFormat.format(value)}';
  }

  /// 格式化日期
  static String formatDate(DateTime date) {
    return _dateFormat.format(date);
  }

  /// 格式化日期时间
  static String formatDateTime(DateTime date) {
    return _dateTimeFormat.format(date);
  }

  /// 格式化相对时间
  static String formatRelativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return formatDate(date);
  }

  /// 格式化数量
  static String formatQuantity(double qty) {
    if (qty == qty.toInt().toDouble()) {
      return qty.toInt().toString();
    }
    return _currencyFormat.format(qty);
  }

  /// 格式化数字（千分位，不带前缀）
  static String formatNumber(double value) {
    return _currencyFormat.format(value);
  }

  /// 格式化价格（不带前缀）
  static String formatPrice(double value, {String? currency}) {
    if (currency == null || currency.isEmpty) {
      return _currencyFormat.format(value);
    }
    return '${currencySymbol(currency)}${_currencyFormat.format(value)}';
  }
}
