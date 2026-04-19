import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 持仓截图识别服务
/// 默认使用智谱 GLM-4V-Flash（国内免费，无需翻墙）
/// 也支持切换到 Google Gemini
class OcrService {
  static const String _prefsKeyProvider = 'ai_provider'; // 'zhipu' or 'gemini'
  static const String _prefsKeyZhipu = 'zhipu_api_key';
  static const String _prefsKeyGemini = 'gemini_api_key';

  // 智谱 API（GLM-4V-Flash，完全免费）
  static const String _zhipuApiUrl = 'https://open.bigmodel.cn/api/paas/v4/chat/completions';
  static const String _zhipuModel = 'glm-4v-flash';

  // Gemini API（备选）
  static const String _geminiModel = 'gemini-2.0-flash-lite';
  static const String _geminiApiBase = 'https://generativelanguage.googleapis.com/v1beta/models';

  static const int _maxImageBytes = 4 * 1024 * 1024;
  static const int _maxRetries = 1;

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 90),
    receiveTimeout: const Duration(seconds: 90),
  ));

  // ===== 配置管理 =====

  static Future<String> getProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKeyProvider) ?? 'zhipu';
  }

  static Future<void> setProvider(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyProvider, provider);
  }

  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString(_prefsKeyProvider) ?? 'zhipu';
    return prefs.getString(provider == 'zhipu' ? _prefsKeyZhipu : _prefsKeyGemini);
  }

  static Future<void> setApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString(_prefsKeyProvider) ?? 'zhipu';
    await prefs.setString(provider == 'zhipu' ? _prefsKeyZhipu : _prefsKeyGemini, apiKey.trim());
  }

  static Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString(_prefsKeyProvider) ?? 'zhipu';
    await prefs.remove(provider == 'zhipu' ? _prefsKeyZhipu : _prefsKeyGemini);
  }

  /// 系统提示词
  static const String _systemPrompt = '''你是一个专业的金融资产数据提取助手。用户会上传各种金融APP的截图，包括但不限于：
- 券商APP的持仓页、资产总览页
- 基金APP的持有基金页、资产明细页
- 银行APP的存款页、理财页、账户总览页
- 任何显示资产/持仓/余额信息的截图

你的任务是从截图中**智能识别并提取所有资产/持仓信息**，返回结构化的JSON数据。

**提取规则：**
1. 尽可能提取每条资产的：证券代码(code)、名称(name)、数量(quantity)、成本价(costPrice)、现价(currentPrice)、市值(marketValue)、资产类型(assetType)、币种(currency)
2. **重要：同时提取盈亏额(profitLoss)和收益率(profitLossPercent)**，截图中显示的盈亏金额、收益率、持仓收益等都要提取，这些信息可以帮助推算缺失的成本价
3. assetType 必须是以下之一：aStock(A股)、hkStock(港股)、usStock(美股)、indexETF(指数ETF)、qdii(QDII)、dividendFund(红利基金)、nasdaqETF(纳指ETF)、bondFund(债基)、moneyFund(货币基金)、mixedFund(混合基金)、wealth(银行理财)、deposit(活期存款)、fixedDeposit(定期存款)、largeDeposit(大额存单)、noticeDeposit(通知存款)、structuredDeposit(结构性存款)、gold(黄金)、insurance(储蓄险)、other(其他)
4. currency 必须是以下之一：CNY(人民币)、HKD(港币)、USD(美元)、EUR(欧元)、GBP(英镑)、JPY(日元)。根据资产类型和截图中的货币符号判断：
   - A股、国内基金、银行理财、存款 → CNY
   - 港股 → HKD（注意：如果截图显示的是港币金额）
   - 美股 → USD（注意：如果截图显示的是美元金额）
   - 如果券商已经帮用户换算成了人民币，currency 填 CNY
   - 注意看截图中的 ¥/￥(CNY)、HK\$/港元(HKD)、\$/US\$(USD) 等货币符号
5. 如果是A股/港股/美股，提取代码和名称
6. 如果是基金，code填基金代码(如161725)，quantity是份额，currentPrice是净值
7. 如果是银行存款/活期，name填"活期存款"/"定期存款"等，quantity填1，currentPrice和marketValue填金额，assetType填deposit/fixedDeposit/largeDeposit等
8. 如果是银行理财产品，name填产品名称，quantity填1，currentPrice和marketValue填当前市值/金额，assetType填wealth
9. 如果是货币基金/零钱通/余额宝类，assetType填moneyFund
10. **缺失的字段填0，但尽量从截图中推算**：如只有"现价"和"收益率"，也要提取，系统会自动推算成本价
11. 忽略广告、推荐、菜单等非资产信息
12. 如果截图中只显示了总资产金额而没有明细，也要提取，name填"账户总资产"，marketValue填总额

**返回格式（严格JSON数组，不要markdown）：**
[
  {"code": "600519", "name": "贵州茅台", "quantity": 100, "costPrice": 1800.50, "currentPrice": 1950.00, "marketValue": 195000.00, "profitLoss": 14950.00, "profitLossPercent": 8.30, "assetType": "aStock", "currency": "CNY"},
  {"code": "161725", "name": "招商中证白酒", "quantity": 5000, "costPrice": 0, "currentPrice": 1.2345, "marketValue": 6172.50, "profitLoss": 500, "profitLossPercent": 8.82, "assetType": "mixedFund", "currency": "CNY"}
]''';

  // ===== 识别入口 =====

  static Future<String> recognizeFromBytes(Uint8List imageBytes, {String language = 'chs', String institution = ''}) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw OcrException('请先在「设置」中配置 API Key\n\n推荐使用智谱AI（国内免费）：\nopen.bigmodel.cn');
    }

    final processedBytes = await _processImage(imageBytes);
    final base64Image = base64Encode(processedBytes);
    final mimeType = _detectMimeType(processedBytes);
    final provider = await getProvider();

    // 智谱对图片大小有限制，如果 base64 太大需要进一步压缩
    if (provider == 'zhipu' && base64Image.length > 2 * 1024 * 1024) {
      // base64 超过 2MB，需要再压缩
      final smallerBytes = await _processImage(processedBytes);
      final smallerBase64 = base64Encode(smallerBytes);
      final institutionHint = institution.isNotEmpty
          ? '\n\n用户告知这是「$institution」的截图，请基于该机构的特点来理解截图内容。'
          : '';
      return await _callZhipuVision(apiKey, smallerBase64, _detectMimeType(smallerBytes), institutionHint);
    }

    final institutionHint = institution.isNotEmpty
        ? '\n\n用户告知这是「$institution」的截图，请基于该机构的特点来理解截图内容。'
        : '';

    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        if (provider == 'zhipu') {
          return await _callZhipuVision(apiKey, base64Image, mimeType, institutionHint);
        } else {
          return await _callGeminiVision(apiKey, base64Image, mimeType, institutionHint);
        }
      } on OcrException catch (e) {
        if (e.message.contains('频繁') && attempt < _maxRetries) {
          await Future.delayed(const Duration(seconds: 5));
          continue;
        }
        rethrow;
      }
    }
    throw OcrException('请求失败，请稍后重试');
  }

  // ===== 智谱 GLM-4V-Flash =====

  static Future<String> _callZhipuVision(String apiKey, String base64Image, String mimeType, String institutionHint) async {
    // GLM-4V-Flash：不支持 system role，提示词合并到 user content
    final prompt = '$_systemPrompt$institutionHint\n\n请从这张截图中提取所有持仓/资产数据，严格按照JSON数组格式返回。';

    final requestBody = {
      'model': _zhipuModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': prompt,
            },
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:$mimeType;base64,$base64Image',
              },
            },
          ],
        },
      ],
    };

    try {
      final response = await _dio.post(
        _zhipuApiUrl,
        data: jsonEncode(requestBody),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          validateStatus: (status) => true,
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data is String ? jsonDecode(response.data) : response.data as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices == null || choices.isEmpty) throw OcrException('AI 未返回结果，请重试');
        final content = choices[0]['message']?['content'] as String? ?? '';
        if (content.trim().isEmpty) throw OcrException('AI 返回内容为空，请确保截图清晰');
        return content.trim();
      } else if (response.statusCode == 400) {
        final msg = _extractErrorMsg(response.data);
        debugPrint('Zhipu 400 error: ${response.data}');
        throw OcrException('请求参数错误: $msg');
      } else if (response.statusCode == 401) {
        throw OcrException('API Key 无效，请在「设置」中重新配置\n\n申请地址：open.bigmodel.cn');
      } else if (response.statusCode == 429) {
        throw OcrException('请求过于频繁，请等待后重试');
      } else {
        final msg = _extractErrorMsg(response.data);
        throw OcrException('AI 服务异常 (${response.statusCode}): $msg');
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ===== Google Gemini（备选） =====

  static Future<String> _callGeminiVision(String apiKey, String base64Image, String mimeType, String institutionHint) async {
    final apiUrl = '$_geminiApiBase/$_geminiModel:generateContent?key=$apiKey';

    final requestBody = {
      'contents': [
        {
          'parts': [
            {'text': '$_systemPrompt$institutionHint'},
            {'inline_data': {'mime_type': mimeType, 'data': base64Image}},
            {'text': '请从这张截图中提取所有持仓/资产数据，严格按照JSON数组格式返回。'},
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'maxOutputTokens': 4096,
        'responseMimeType': 'application/json',
      },
    };

    try {
      final response = await _dio.post(
        apiUrl,
        data: jsonEncode(requestBody),
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (status) => true,
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data is String ? jsonDecode(response.data) : response.data as Map<String, dynamic>;
        final candidates = data['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) throw OcrException('AI 未返回结果');
        final text = candidates[0]['content']?['parts']?[0]?['text'] as String? ?? '';
        if (text.trim().isEmpty) throw OcrException('AI 返回内容为空');
        return text.trim();
      } else if (response.statusCode == 429) {
        throw OcrException('请求过于频繁，请等待 1 分钟后重试');
      } else if (response.statusCode == 400 || response.statusCode == 403) {
        throw OcrException('API Key 无效，请在「设置」中重新配置');
      } else {
        throw OcrException('AI 服务异常 (${response.statusCode})');
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ===== 工具方法 =====

  static OcrException _handleDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return OcrException('网络超时，请检查网络后重试');
    }
    if (e.type == DioExceptionType.connectionError) {
      return OcrException('网络连接失败，请检查网络设置');
    }
    return OcrException('网络错误: ${e.message ?? "未知错误"}');
  }

  static String _extractErrorMsg(dynamic data) {
    try {
      final json = data is String ? jsonDecode(data) : data as Map<String, dynamic>;
      return json['error']?['message'] as String? ?? json['msg'] as String? ?? '未知错误';
    } catch (_) {
      return '未知错误';
    }
  }

  static Future<Uint8List> _processImage(Uint8List imageBytes) async {
    if (imageBytes.length <= _maxImageBytes) return imageBytes;
    try {
      final targetWidth = _calculateTargetWidth(imageBytes.length);
      final codec = await ui.instantiateImageCodec(imageBytes, targetWidth: targetWidth);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      codec.dispose();
      if (byteData == null) return imageBytes;
      final result = byteData.buffer.asUint8List();
      if (result.length > _maxImageBytes) return _processImage(result);
      return result;
    } catch (e) {
      debugPrint('Image compression failed: $e');
      return imageBytes;
    }
  }

  static int _calculateTargetWidth(int originalSize) {
    final ratio = _maxImageBytes / originalSize;
    final scale = ratio < 1 ? (ratio * 0.8).clamp(0.3, 0.9) : 1.0;
    return (1440 * scale).round().clamp(720, 2048);
  }

  static String _detectMimeType(Uint8List bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return 'image/jpeg';
    if (bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return 'image/png';
    if (bytes.length >= 4 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return 'image/gif';
    return 'image/jpeg';
  }

  /// 验证 API Key（不消耗生成配额）
  static Future<bool> testApiKey(String apiKey) async {
    final provider = await getProvider();
    try {
      if (provider == 'zhipu') {
        // 智谱：用一个简单的文本请求测试
        final response = await _dio.post(
          _zhipuApiUrl,
          data: jsonEncode({
            'model': 'glm-4-flash',
            'messages': [{'role': 'user', 'content': 'hi'}],
          }),
          options: Options(
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
            validateStatus: (_) => true,
          ),
        );
        return response.statusCode == 200;
      } else {
        final response = await _dio.get(
          'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
          options: Options(validateStatus: (_) => true),
        );
        return response.statusCode == 200;
      }
    } catch (_) {
      return false;
    }
  }
}

class OcrException implements Exception {
  final String message;
  OcrException(this.message);

  @override
  String toString() => message;
}
