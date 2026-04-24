import 'package:shared_preferences/shared_preferences.dart';

/// 是否在调用 AI 前弹出提示词编辑框（首页/持仓/分析共用）
class AiPromptPrefs {
  AiPromptPrefs._();

  static const String _keyPreviewBeforeRun = 'ai_preview_prompt_before_run';

  static Future<bool> getPreviewPromptBeforeRun() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_keyPreviewBeforeRun) ?? false;
  }

  static Future<void> setPreviewPromptBeforeRun(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyPreviewBeforeRun, value);
  }
}
