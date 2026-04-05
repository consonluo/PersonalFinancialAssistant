/// String 扩展方法
extension StringExtensions on String {
  /// 是否为有效的股票代码
  bool get isValidStockCode {
    return RegExp(r'^(\d{6}|[A-Z]{1,5})(\.(SH|SZ|HK|US|O|N|OF))?$')
        .hasMatch(toUpperCase().trim());
  }

  /// 是否为有效的基金代码
  bool get isValidFundCode {
    final code = replaceAll(RegExp(r'\.(OF|SZ|SH)$'), '');
    return code.length == 6 && RegExp(r'^\d{6}$').hasMatch(code);
  }

  /// 提取纯数字代码
  String get pureCode {
    return replaceAll(RegExp(r'\.(SH|SZ|HK|US|O|N|OF)$', caseSensitive: false), '').trim();
  }

  /// 截断显示
  String truncate(int maxLength, {String ellipsis = '...'}) {
    if (length <= maxLength) return this;
    return '${substring(0, maxLength - ellipsis.length)}$ellipsis';
  }

  /// 首字母大写
  String get capitalize {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
