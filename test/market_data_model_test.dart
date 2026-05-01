import 'package:flutter_test/flutter_test.dart';
import 'package:personal_financial_assistant/data/models/market_data_model.dart';

void main() {
  test('MarketDataModel defaults currency to CNY', () {
    final m = MarketDataModel(
      assetCode: '600519',
      name: '茅台',
      price: 1800,
      updatedAt: DateTime.utc(2025, 1, 1),
    );
    expect(m.currency, 'CNY');
  });

  test('MarketDataModel.fromJson reads currency', () {
    final m = MarketDataModel.fromJson({
      'assetCode': 'AAPL',
      'name': 'Apple',
      'price': 200.0,
      'change': 1.0,
      'changePercent': 0.5,
      'volume': 1000.0,
      'updatedAt': '2025-01-01T12:00:00.000Z',
      'currency': 'USD',
    });
    expect(m.currency, 'USD');
    expect(m.price, 200.0);
  });

  test('MarketDataModel.toJson includes currency', () {
    final m = MarketDataModel(
      assetCode: '00700',
      name: '腾讯',
      price: 350,
      updatedAt: DateTime.utc(2025, 6, 1),
      currency: 'HKD',
    );
    final j = m.toJson();
    expect(j['currency'], 'HKD');
  });
}
