import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'ocr_service.dart';

/// AI 文本分析服务
/// 复用智谱/Gemini API Key 进行文本对话分析
class AiService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 120),
    receiveTimeout: const Duration(seconds: 120),
  ));

  // 智谱文本模型（免费）
  static const String _zhipuTextModel = 'glm-4-flash';
  static const String _zhipuApiUrl = 'https://open.bigmodel.cn/api/paas/v4/chat/completions';

  // Gemini 文本模型
  static const String _geminiTextModel = 'gemini-2.0-flash-lite';
  static const String _geminiApiBase = 'https://generativelanguage.googleapis.com/v1beta/models';

  /// 发送文本分析请求（非流式）
  static Future<String> chat(String prompt) async {
    final apiKey = await OcrService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw AiException('请先在「设置」中配置 API Key');
    }
    final provider = await OcrService.getProvider();

    if (provider == 'zhipu') {
      return _chatZhipu(apiKey, prompt);
    } else {
      return _chatGemini(apiKey, prompt);
    }
  }

  /// 流式聊天接口 — 返回 Stream<String>，每次 yield 一段增量文本
  static Stream<String> chatStream(String prompt) async* {
    final apiKey = await OcrService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw AiException('请先在「设置」中配置 API Key');
    }
    final provider = await OcrService.getProvider();

    if (provider == 'zhipu') {
      yield* _chatZhipuStream(apiKey, prompt);
    } else {
      yield* _chatGeminiStream(apiKey, prompt);
    }
  }

  // ===== 智谱非流式 =====
  static Future<String> _chatZhipu(String apiKey, String prompt) async {
    try {
      final response = await _dio.post(
        _zhipuApiUrl,
        data: jsonEncode({
          'model': _zhipuTextModel,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        }),
        options: Options(
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
          validateStatus: (_) => true,
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data is String ? jsonDecode(response.data) : response.data;
        return data['choices']?[0]?['message']?['content'] as String? ?? '';
      }
      throw AiException('AI 服务异常 (${response.statusCode})');
    } on DioException catch (e) {
      throw AiException('网络错误: ${e.message ?? "未知"}');
    }
  }

  // ===== 智谱流式 SSE =====
  static Stream<String> _chatZhipuStream(String apiKey, String prompt) async* {
    try {
      final response = await _dio.post<ResponseBody>(
        _zhipuApiUrl,
        data: jsonEncode({
          'model': _zhipuTextModel,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'stream': true,
        }),
        options: Options(
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
          responseType: ResponseType.stream,
          validateStatus: (_) => true,
        ),
      );

      if (response.statusCode != 200) {
        throw AiException('AI 服务异常 (${response.statusCode})');
      }

      final stream = response.data!.stream;
      String buffer = '';

      await for (final chunk in stream) {
        buffer += utf8.decode(chunk);
        // SSE: 按行解析
        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);

          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') return;
            try {
              final json = jsonDecode(data);
              final delta = json['choices']?[0]?['delta']?['content'] as String?;
              if (delta != null && delta.isNotEmpty) {
                yield delta;
              }
            } catch (_) {
              // 忽略解析错误行
            }
          }
        }
      }
    } on DioException catch (e) {
      throw AiException('网络错误: ${e.message ?? "未知"}');
    }
  }

  // ===== Gemini 非流式 =====
  static Future<String> _chatGemini(String apiKey, String prompt) async {
    try {
      final response = await _dio.post(
        '$_geminiApiBase/$_geminiTextModel:generateContent?key=$apiKey',
        data: jsonEncode({
          'contents': [{'parts': [{'text': prompt}]}],
        }),
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (_) => true,
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data is String ? jsonDecode(response.data) : response.data;
        return data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? '';
      }
      throw AiException('AI 服务异常 (${response.statusCode})');
    } on DioException catch (e) {
      throw AiException('网络错误: ${e.message ?? "未知"}');
    }
  }

  // ===== Gemini 流式 SSE =====
  static Stream<String> _chatGeminiStream(String apiKey, String prompt) async* {
    try {
      final response = await _dio.post<ResponseBody>(
        '$_geminiApiBase/$_geminiTextModel:streamGenerateContent?alt=sse&key=$apiKey',
        data: jsonEncode({
          'contents': [{'parts': [{'text': prompt}]}],
        }),
        options: Options(
          headers: {'Content-Type': 'application/json'},
          responseType: ResponseType.stream,
          validateStatus: (_) => true,
        ),
      );

      if (response.statusCode != 200) {
        throw AiException('AI 服务异常 (${response.statusCode})');
      }

      final stream = response.data!.stream;
      String buffer = '';

      await for (final chunk in stream) {
        buffer += utf8.decode(chunk);
        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);

          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data.isEmpty) continue;
            try {
              final json = jsonDecode(data);
              final text = json['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
              if (text != null && text.isNotEmpty) {
                yield text;
              }
            } catch (_) {}
          }
        }
      }
    } on DioException catch (e) {
      throw AiException('网络错误: ${e.message ?? "未知"}');
    }
  }

  /// 智能分类持仓（非流式，返回 JSON）
  static Future<String> classifyHoldings(List<Map<String, dynamic>> holdings) async {
    final holdingsJson = jsonEncode(holdings);
    final prompt = '''你是一个专业的金融资产分类专家。请对以下持仓数据进行智能分类。

当前持仓数据：
$holdingsJson

请对每条持仓重新判断资产类型，assetType 必须是以下之一：
aStock(A股)、hkStock(港股)、usStock(美股)、indexETF(指数ETF)、qdii(QDII)、dividendFund(红利基金)、nasdaqETF(纳指ETF)、bondFund(债券基金)、moneyFund(货币基金)、mixedFund(混合基金)、wealth(银行理财)、deposit(存款)、other(其他)

返回严格JSON数组（不要markdown），每条包含 id 和新的 assetType：
[{"id": "原始id", "assetType": "新类型", "reason": "分类理由"}]''';

    return chat(prompt);
  }

  /// 智能分类持仓（流式）
  static Stream<String> classifyHoldingsStream(List<Map<String, dynamic>> holdings) {
    final holdingsJson = jsonEncode(holdings);
    final prompt = '''你是一个专业的金融资产分类专家。请对以下持仓数据进行智能分类。

当前持仓数据：
$holdingsJson

请对每条持仓重新判断资产类型，assetType 必须是以下之一：
aStock(A股)、hkStock(港股)、usStock(美股)、indexETF(指数ETF)、qdii(QDII)、dividendFund(红利基金)、nasdaqETF(纳指ETF)、bondFund(债券基金)、moneyFund(货币基金)、mixedFund(混合基金)、wealth(银行理财)、deposit(存款)、other(其他)

返回严格JSON数组（不要markdown），每条包含 id 和新的 assetType：
[{"id": "原始id", "assetType": "新类型", "reason": "分类理由"}]''';

    return chatStream(prompt);
  }

  /// 资产健康度分析 Prompt
  static String _buildAnalyzePrompt({
    required List<Map<String, dynamic>> holdings,
    required double totalAssets,
    required double totalLiability,
    required List<Map<String, dynamic>> categories,
    List<Map<String, dynamic>>? investmentPlans,
  }) {
    final plansSection = (investmentPlans != null && investmentPlans.isNotEmpty)
        ? '''

**定投计划（共${investmentPlans.length}个）：**
${investmentPlans.map((p) => '- ${p['name']}(${p['code']}) 每次¥${p['amount']} 频率:${p['frequency']} 状态:${p['isActive'] == true ? '运行中' : '已暂停'}').join('\n')}'''
        : '';

    return '''你是一个专业的家庭资产配置顾问。请对以下家庭资产情况进行全面分析。

**资产概况：**
- 总资产：¥${totalAssets.toStringAsFixed(2)}
- 总负债：¥${totalLiability.toStringAsFixed(2)}
- 净资产：¥${(totalAssets - totalLiability).toStringAsFixed(2)}

**资产分类分布：**
${categories.map((c) => '- ${c['name']}：¥${c['value']} (${c['percent']}%)').join('\n')}

**持仓明细（共${holdings.length}笔）：**
${holdings.map((h) => '- ${h['name']}(${h['code']}) 类型:${h['type']} 市值:¥${h['marketValue']} 盈亏:${h['pnl']}%').join('\n')}$plansSection

请从以下维度进行分析，使用中文，语言简洁直接：

## 1. 资产健康度评分（满分100分）
给出综合评分和简要理由。

## 2. 资产配置分析
分析当前配置是否合理，各类资产占比是否均衡。

## 3. 风险提示
指出潜在风险点（如过度集中、高风险资产占比过高等）。

## 4. 优化建议
给出 3-5 条具体可操作的优化建议。

## 5. 持仓点评
对主要持仓给出简短点评（趋势、估值等）。${investmentPlans != null && investmentPlans.isNotEmpty ? '''

## 6. 定投计划评估
分析当前定投计划是否合理：标的选择、金额、频率是否匹配家庭财务状况，给出调整建议。''' : ''}''';
  }

  /// 资产健康度分析（非流式）
  static Future<String> analyzePortfolio({
    required List<Map<String, dynamic>> holdings,
    required double totalAssets,
    required double totalLiability,
    required List<Map<String, dynamic>> categories,
    List<Map<String, dynamic>>? investmentPlans,
  }) async {
    return chat(_buildAnalyzePrompt(
      holdings: holdings,
      totalAssets: totalAssets,
      totalLiability: totalLiability,
      categories: categories,
      investmentPlans: investmentPlans,
    ));
  }

  /// 资产健康度分析（流式）
  static Stream<String> analyzePortfolioStream({
    required List<Map<String, dynamic>> holdings,
    required double totalAssets,
    required double totalLiability,
    required List<Map<String, dynamic>> categories,
    List<Map<String, dynamic>>? investmentPlans,
  }) {
    return chatStream(_buildAnalyzePrompt(
      holdings: holdings,
      totalAssets: totalAssets,
      totalLiability: totalLiability,
      categories: categories,
      investmentPlans: investmentPlans,
    ));
  }
}

class AiException implements Exception {
  final String message;
  AiException(this.message);
  @override
  String toString() => message;
}
