import 'package:flutter_test/flutter_test.dart';
import 'package:personal_financial_assistant/core/utils/format_utils.dart';

void main() {
  group('FormatUtils.currencySymbol', () {
    test('CNY and empty default to ¥', () {
      expect(FormatUtils.currencySymbol('CNY'), '¥');
      expect(FormatUtils.currencySymbol(''), '¥');
    });
    test('known codes', () {
      expect(FormatUtils.currencySymbol('USD'), r'$');
      expect(FormatUtils.currencySymbol('HKD'), r'HK$');
      expect(FormatUtils.currencySymbol('EUR'), '€');
    });
  });

  group('FormatUtils.formatFullCurrency with currency', () {
    test('uses correct prefix for USD', () {
      expect(FormatUtils.formatFullCurrency(1234.56, currency: 'USD'), r'$1,234.56');
    });
    test('uses ¥ for CNY', () {
      expect(FormatUtils.formatFullCurrency(100, currency: 'CNY'), '¥100.00');
    });
  });

  group('FormatUtils.formatChange with currency', () {
    test('positive with USD', () {
      expect(FormatUtils.formatChange(10.5, currency: 'USD'), r'+$10.50');
    });
  });
}
