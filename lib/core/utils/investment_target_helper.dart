import 'dart:convert';
import 'ai_service.dart';

class TargetSuggestion {
  final String target;
  final List<String> tags;

  const TargetSuggestion({required this.target, required this.tags});
}

class InvestmentTargetHelper {
  InvestmentTargetHelper._();

  static TargetSuggestion inferLocal(String code, String name) {
    final n = name.toUpperCase();
    final c = code.toUpperCase();
    final tags = <String>[];
    String target = '';

    if (n.contains('纳斯达克') || n.contains('NASDAQ') || n.contains('纳指') || c == 'QQQ') {
      target = '纳指';
      tags.addAll(['纳指', '科技']);
    }
    if (n.contains('标普') || n.contains('S&P') || c == 'SPY' || c == 'VOO') {
      target = target.isEmpty ? '美股宽基' : target;
      tags.addAll(['标普500', '美股宽基']);
    }
    if (n.contains('红利') || n.contains('高股息') || n.contains('分红')) {
      target = target.isEmpty ? '红利' : target;
      tags.add('红利');
    }
    if (n.contains('消费')) tags.add('消费');
    if (n.contains('科技') || n.contains('半导体') || n.contains('芯片')) tags.add('科技');
    if (n.contains('国防') || n.contains('军工')) tags.add('国防');
    if (n.contains('沪深300') || n.contains('中证500') || n.contains('中证1000') || n.contains('上证50')) {
      target = target.isEmpty ? 'A股宽基' : target;
      tags.add('A股宽基');
    }
    if (RegExp(r'^\d{6}$').hasMatch(c)) tags.add('A股');
    if (RegExp(r'^[A-Z]{1,5}$').hasMatch(c)) tags.add('美股');
    if (RegExp(r'^[0689]\d{4}$').hasMatch(code)) tags.add('港股');

    if (target.isEmpty) {
      if (tags.isNotEmpty) {
        target = tags.first;
      } else {
        target = '其他';
      }
    }
    return TargetSuggestion(target: target, tags: tags.toSet().toList());
  }

  static Future<TargetSuggestion> suggestByAi(String code, String name) async {
    final fallback = inferLocal(code, name);
    final prompt = '''
你是投资标的识别助手。根据输入返回 JSON：
{"target":"投资标的","tags":["标签1","标签2"]}
要求：
1) target 不超过8个字
2) tags 2-5个，简短词
3) 仅返回 JSON，不要解释

输入：
{"code":"$code","name":"$name"}
''';
    try {
      final text = await AiService.chat(prompt).timeout(const Duration(seconds: 12));
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start < 0 || end <= start) return fallback;
      final parsed = jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
      final target = (parsed['target'] as String?)?.trim();
      final tagsRaw = parsed['tags'];
      final tags = <String>[];
      if (tagsRaw is List) {
        for (final t in tagsRaw) {
          final s = t.toString().trim();
          if (s.isNotEmpty) tags.add(s);
        }
      }
      if (target == null || target.isEmpty) return fallback;
      return TargetSuggestion(target: target, tags: tags.toSet().toList());
    } catch (_) {
      return fallback;
    }
  }
}
