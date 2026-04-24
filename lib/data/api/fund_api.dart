import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/market_data_model.dart';
import 'market_api_client.dart';

/// 天天基金 API - 基金净值查询（估值接口 + 详情接口备用）
class FundApi implements MarketApiClient {
  final Dio _dio;

  FundApi({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'Referer': 'https://fund.eastmoney.com',
    },
  ));

  @override
  Future<List<MarketDataModel>> getQuotes(List<String> codes) async {
    final results = <MarketDataModel>[];
    final failedCodes = <String>[];

    for (final code in codes) {
      final pureCode = code.replaceAll(RegExp(r'\.(OF|SZ|SH)$', caseSensitive: false), '');
      if (!RegExp(r'^\d{6}$').hasMatch(pureCode)) continue;
      try {
        final result = await _getEstimate(pureCode);
        if (result != null) {
          results.add(result);
        } else {
          failedCodes.add(pureCode);
        }
      } catch (e) {
        debugPrint('[FundApi] estimate($pureCode) failed: $e');
        failedCodes.add(pureCode);
      }
    }

    // 对估值接口拿不到的基金，走详情接口批量获取
    if (failedCodes.isNotEmpty) {
      try {
        final fallback = await _getFundInfo(failedCodes);
        results.addAll(fallback);
        debugPrint('[FundApi] fallback got ${fallback.length}/${failedCodes.length} for $failedCodes');
      } catch (e) {
        debugPrint('[FundApi] fallback failed: $e');
      }
    }

    return results;
  }

  @override
  Future<MarketDataModel?> getQuote(String code) async {
    final results = await getQuotes([code]);
    return results.isEmpty ? null : results.first;
  }

  /// 天天基金实时估值接口（适用于权益类/混合型/债券型基金盘中估值）
  Future<MarketDataModel?> _getEstimate(String pureCode) async {
    final url = 'https://fundgz.1234567.com.cn/js/$pureCode.js';
    final response = await _dio.get(url, options: Options(
      responseType: ResponseType.plain,
      validateStatus: (status) => status != null && status < 500,
    ));

    if (response.statusCode != 200) return null;

    final text = response.data?.toString() ?? '';
    return _parseEstimateResponse(pureCode, text);
  }

  /// 东方财富基金详情接口（支持货币基金、无估值的债基等）
  Future<List<MarketDataModel>> _getFundInfo(List<String> codes) async {
    final url = 'https://fundmobapi.eastmoney.com/FundMNewApi/FundMNFInfo';
    final response = await _dio.get(url, queryParameters: {
      'plat': 'Android',
      'appType': 'ttjj',
      'product': 'EFund',
      'Version': '1',
      'deviceid': '1',
      'Fcodes': codes.join(','),
    });

    if (response.statusCode != 200) return [];

    final data = response.data;
    final rawData = data is String ? jsonDecode(data) : data;
    final List<dynamic> items = rawData['Datas'] ?? [];
    final expansion = rawData['Expansion'] as Map<String, dynamic>?;
    final fsrq = expansion?['FSRQ']?.toString();
    final results = <MarketDataModel>[];

    for (final item in items) {
      final code = item['FCODE']?.toString() ?? '';
      final name = item['SHORTNAME']?.toString() ?? code;
      final navChgRt = item['NAVCHGRT']?.toString() ?? '--';
      final gsz = double.tryParse(item['GSZ']?.toString() ?? '');
      final gszzl = double.tryParse(item['GSZZL']?.toString() ?? '');
      final dwjz = double.tryParse(item['DWJZ']?.toString() ?? '');
      final nav = double.tryParse(item['NAV']?.toString() ?? '');
      final pdate = item['PDATE']?.toString() ?? fsrq;
      final dataTime = pdate != null ? (DateTime.tryParse(pdate) ?? DateTime.now()) : DateTime.now();

      if (navChgRt == '--') {
        results.add(MarketDataModel(
          assetCode: code,
          name: name,
          price: 1.0,
          change: 0.0,
          changePercent: (nav ?? 0) / 10000 * 100,
          updatedAt: dataTime,
        ));
      } else {
        final chgPct = double.tryParse(navChgRt) ?? 0.0;
        final price = gsz ?? dwjz ?? 0.0;
        if (price <= 0) continue;
        final prevPrice = chgPct != 0 ? price / (1 + chgPct / 100) : price;
        results.add(MarketDataModel(
          assetCode: code,
          name: name,
          price: price,
          change: price - prevPrice,
          changePercent: chgPct,
          updatedAt: dataTime,
        ));
      }
    }
    return results;
  }

  MarketDataModel? _parseEstimateResponse(String code, String text) {
    // 格式: jsonpgz({"fundcode":"000001","name":"xxx","jzrq":"2024-01-01",
    //        "dwjz":"1.0","gsz":"1.01","gszzl":"1.00%","gztime":"2024-01-02 15:00"});
    final match = RegExp(r'\{[^}]+\}').firstMatch(text);
    if (match == null) return null;

    final jsonStr = match.group(0)!;
    final fields = <String, String>{};

    for (final fieldMatch in RegExp(r'"(\w+)":"([^"]*)"').allMatches(jsonStr)) {
      fields[fieldMatch.group(1)!] = fieldMatch.group(2)!;
    }

    final name = fields['name'] ?? code;
    final dwjz = double.tryParse(fields['dwjz'] ?? '') ?? 0;
    final gszRaw = double.tryParse(fields['gsz'] ?? '') ?? 0;
    final gszzl = double.tryParse(
        (fields['gszzl'] ?? '0').replaceAll('%', '')) ?? 0;

    final hasEstimate = gszRaw > 0 && gszzl != 0;
    final price = hasEstimate ? gszRaw : dwjz;
    final change = hasEstimate ? gszRaw - dwjz : 0.0;
    final changePercent = hasEstimate ? gszzl : 0.0;

    if (price <= 0) return null;

    // 使用 gztime（估值时间）或 jzrq（净值日期）作为数据时间
    DateTime dataTime;
    final gztime = fields['gztime'];
    final jzrq = fields['jzrq'];
    if (gztime != null && gztime.isNotEmpty) {
      dataTime = DateTime.tryParse(gztime.replaceFirst(' ', 'T')) ?? DateTime.now();
    } else if (jzrq != null && jzrq.isNotEmpty) {
      dataTime = DateTime.tryParse(jzrq) ?? DateTime.now();
    } else {
      dataTime = DateTime.now();
    }

    return MarketDataModel(
      assetCode: code,
      name: name,
      price: price,
      change: change,
      changePercent: changePercent,
      updatedAt: dataTime,
    );
  }
}
