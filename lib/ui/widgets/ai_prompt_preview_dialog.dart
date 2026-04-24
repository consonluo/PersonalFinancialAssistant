import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// 在调用 AI 前展示并编辑提示词；返回编辑后的文本，取消则返回 null。
Future<String?> showAiPromptPreviewDialog(
  BuildContext context, {
  required String title,
  required String initialPrompt,
  String confirmLabel = '确认并调用 AI',
}) async {
  final controller = TextEditingController(text: initialPrompt);
  final focus = FocusNode();

  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: MediaQuery.sizeOf(ctx).width.clamp(320, 720),
          height: MediaQuery.sizeOf(ctx).height * 0.55,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '可编辑下方提示词后确认调用；留空将取消。',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                    hintText: '提示词…',
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('提示词不能为空')),
                );
                return;
              }
              Navigator.pop(ctx, t);
            },
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );

  controller.dispose();
  focus.dispose();
  return result;
}
