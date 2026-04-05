import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/ocr_service.dart';
import '../../providers/current_role_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/database_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String? _apiKey;
  String _provider = 'zhipu';
  bool _apiKeyLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final key = await OcrService.getApiKey();
    final provider = await OcrService.getProvider();
    setState(() {
      _apiKey = key;
      _provider = provider;
      _apiKeyLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDemo = ref.watch(isDemoModeProvider);
    final familyName = ref.watch(familyNameProvider);
    final familyId = ref.watch(familyIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (familyName.isNotEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.home, color: AppColors.primary),
                title: Text(familyName),
                subtitle: Text(isDemo ? '演示模式' : '正式家庭'),
              ),
            ),
          if (familyId != null && familyId.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.vpn_key, color: AppColors.info),
                title: const Text('家庭账号 ID'),
                subtitle: Text(familyId, style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1)),
                trailing: IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: familyId));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // AI 截图识别配置
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('AI 截图识别', style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          Card(
            child: ListTile(
              leading: Icon(
                _apiKeyLoaded && _apiKey != null && _apiKey!.isNotEmpty
                    ? Icons.check_circle
                    : Icons.warning_amber,
                color: _apiKeyLoaded && _apiKey != null && _apiKey!.isNotEmpty
                    ? AppColors.success
                    : AppColors.warning,
              ),
              title: Text(_provider == 'zhipu' ? '智谱AI（推荐，国内免费）' : 'Google Gemini'),
              subtitle: Text(
                _apiKeyLoaded && _apiKey != null && _apiKey!.isNotEmpty
                    ? '已配置 (${_apiKey!.length > 10 ? '${_apiKey!.substring(0, 10)}...' : _apiKey!})'
                    : '未配置（截图识别需要 API Key）',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showApiKeyDialog(context),
            ),
          ),
          const SizedBox(height: 16),

          // 数据管理
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('数据', style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.storage, color: AppColors.info),
              title: const Text('数据管理'),
              subtitle: const Text('导入、导出、同步数据'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/data-manage'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.money_off_outlined, color: AppColors.error),
              title: const Text('负债管理'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/liabilities'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.balance, color: AppColors.primary),
              title: const Text('资产负债表'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/balance-sheet'),
            ),
          ),
          const SizedBox(height: 24),

          // 退出登录
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppColors.error),
              title: const Text('退出登录', style: TextStyle(color: AppColors.error)),
              subtitle: const Text('清除本地数据并返回登录页'),
              onTap: () => _logout(context),
            ),
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              '${AppConstants.appName} v${AppConstants.appVersion}',
              style: const TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showApiKeyDialog(BuildContext context) async {
    final controller = TextEditingController(text: _apiKey ?? '');
    bool isTesting = false;
    String dialogProvider = _provider;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isZhipu = dialogProvider == 'zhipu';
          return AlertDialog(
            title: const Text('AI 截图识别配置'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择 AI 服务商', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('智谱AI（推荐）'),
                          selected: isZhipu,
                          onSelected: (_) {
                            setDialogState(() { dialogProvider = 'zhipu'; controller.clear(); });
                          },
                          labelStyle: TextStyle(color: isZhipu ? Colors.white : AppColors.textPrimary, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Google Gemini'),
                          selected: !isZhipu,
                          onSelected: (_) {
                            setDialogState(() { dialogProvider = 'gemini'; controller.clear(); });
                          },
                          labelStyle: TextStyle(color: !isZhipu ? Colors.white : AppColors.textPrimary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isZhipu
                        ? '智谱AI GLM-4V-Flash：国内直连、完全免费'
                        : 'Google Gemini：需翻墙，有免费额度',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => launchUrl(Uri.parse(isZhipu
                        ? 'https://open.bigmodel.cn/usercenter/apikeys'
                        : 'https://aistudio.google.com/apikey')),
                    child: Text(
                      isZhipu ? '前往智谱AI申请免费 Key →' : '前往 Google AI Studio 申请 →',
                      style: const TextStyle(color: AppColors.primary, fontSize: 13, decoration: TextDecoration.underline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(hintText: '粘贴 API Key', labelText: 'API Key', isDense: true),
                    maxLines: 1,
                  ),
                  if (isTesting) ...[
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('验证中...', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (_apiKey != null && _apiKey!.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await OcrService.clearApiKey();
                    setState(() => _apiKey = null);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('清除', style: TextStyle(color: AppColors.error)),
                ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              ElevatedButton(
                onPressed: isTesting
                    ? null
                    : () async {
                        final key = controller.text.trim();
                        if (key.isEmpty) return;
                        setDialogState(() => isTesting = true);

                        // 先保存 provider 设置
                        await OcrService.setProvider(dialogProvider);
                        final valid = await OcrService.testApiKey(key);

                        if (!ctx.mounted) return;
                        if (valid) {
                          await OcrService.setApiKey(key);
                          setState(() { _apiKey = key; _provider = dialogProvider; });
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API Key 配置成功')));
                        } else {
                          setDialogState(() => isTesting = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('API Key 无效，请检查后重试')));
                        }
                      },
                child: const Text('验证并保存'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
  }

  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出登录将清除本地数据。\n如需保留数据，请先在「数据管理」中导出。\n\n确定退出？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出登录', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ref.read(autoSyncProvider).syncUp();
    } catch (_) {}

    final db = ref.read(databaseProvider);
    await db.clearAllData();

    ref.read(familyNameProvider.notifier).state = '';
    ref.read(isDemoModeProvider.notifier).state = false;
    await ref.read(familyIdProvider.notifier).clearFamilyId();
    await ref.read(currentRoleProvider.notifier).clearRole();
    await ref.read(syncConfigProvider.notifier).clearConfig();
    await ref.read(passwordHashProvider.notifier).clear();
    (await SharedPreferences.getInstance()).remove('family_name');

    if (context.mounted) {
      context.go('/welcome');
    }
  }
}
