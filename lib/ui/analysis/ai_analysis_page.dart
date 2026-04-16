import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/ai_service.dart';

/// AI 分析结果展示页（支持流式输出）
class AiAnalysisPage extends StatefulWidget {
  final String title;
  /// 如果传入 content 则直接显示；如果传入 streamParams 则流式加载
  final String content;
  final Map<String, dynamic>? streamParams;

  const AiAnalysisPage({
    super.key,
    required this.title,
    this.content = '',
    this.streamParams,
  });

  @override
  State<AiAnalysisPage> createState() => _AiAnalysisPageState();
}

class _AiAnalysisPageState extends State<AiAnalysisPage> {
  String _content = '';
  bool _isLoading = false;
  String? _error;
  StreamSubscription<String>? _subscription;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.streamParams != null) {
      _startStreaming();
    } else {
      _content = widget.content;
    }
  }

  void _startStreaming() {
    setState(() {
      _isLoading = true;
      _error = null;
      _content = '';
    });

    final params = widget.streamParams!;
    final stream = AiService.analyzePortfolioStream(
      holdings: List<Map<String, dynamic>>.from(params['holdings']),
      totalAssets: params['totalAssets'] as double,
      totalLiability: params['totalLiability'] as double,
      categories: List<Map<String, dynamic>>.from(params['categories']),
      investmentPlans: params['investmentPlans'] != null
          ? List<Map<String, dynamic>>.from(params['investmentPlans'])
          : null,
    );

    _subscription = stream.listen(
      (delta) {
        if (mounted) {
          setState(() => _content += delta);
          // 自动滚动到底部
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOut,
              );
            }
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = e.toString();
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
            ),
        ],
      ),
      body: _error != null && _content.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 14), textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 16),
                  if (widget.streamParams != null)
                    ElevatedButton.icon(
                      onPressed: _startStreaming,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                ],
              ),
            )
          : _content.trim().isEmpty && !_isLoading
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome, size: 48, color: AppColors.textHint),
                      const SizedBox(height: 12),
                      const Text('分析数据已过期', style: TextStyle(color: AppColors.textHint, fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text('请返回首页重新发起 AI 分析', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).canPop() ? Navigator.pop(context) : context.go('/dashboard'),
                        icon: const Icon(Icons.home),
                        label: const Text('返回首页'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMarkdown(_content),
                      if (_isLoading) ...[
                        const SizedBox(height: 8),
                        _buildCursor(),
                      ],
                      if (_error != null && _content.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber, color: AppColors.error, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text('传输中断: $_error', style: const TextStyle(color: AppColors.error, fontSize: 13))),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }

  /// 打字机光标效果
  Widget _buildCursor() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      builder: (_, value, __) => Opacity(
        opacity: value > 0.5 ? 1.0 : 0.3,
        child: Container(
          width: 8,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
      onEnd: () {
        if (mounted && _isLoading) setState(() {});
      },
    );
  }

  Widget _buildMarkdown(String text) {
    final lines = text.split('\n');
    final widgets = <Widget>[];

    for (final line in lines) {
      if (line.startsWith('## ')) {
        widgets.add(const SizedBox(height: 16));
        widgets.add(Text(
          line.substring(3).trim(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary),
        ));
        widgets.add(const Divider(height: 16));
      } else if (line.startsWith('# ')) {
        widgets.add(const SizedBox(height: 12));
        widgets.add(Text(
          line.substring(2).trim(),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ));
        widgets.add(const SizedBox(height: 8));
      } else if (line.startsWith('- ') || line.startsWith('• ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Expanded(child: Text(line.substring(2).trim(), style: const TextStyle(fontSize: 14, height: 1.5))),
            ],
          ),
        ));
      } else if (line.startsWith('**') && line.endsWith('**')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(line.replaceAll('**', ''), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ));
      } else if (line.trim().isNotEmpty) {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(line, style: const TextStyle(fontSize: 14, height: 1.6)),
        ));
      } else {
        widgets.add(const SizedBox(height: 8));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }
}
