import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/crypto_utils.dart';
import '../../providers/database_provider.dart';
import '../../providers/current_role_provider.dart';
import '../../providers/sync_provider.dart';
import '../../data/sync/data_serializer.dart';

class LoginFamilyPage extends ConsumerStatefulWidget {
  const LoginFamilyPage({super.key});

  @override
  ConsumerState<LoginFamilyPage> createState() => _LoginFamilyPageState();
}

class _LoginFamilyPageState extends ConsumerState<LoginFamilyPage> {
  final _familyIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String _loadingMessage = '';
  bool _obscurePassword = true;

  @override
  void dispose() {
    _familyIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录已有家庭'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 方式一：家庭账号 + 密码登录
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.family_restroom, color: AppColors.primary, size: 26),
                        SizedBox(width: 12),
                        Text('家庭账号登录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('输入家庭账号 ID 和密码，从云端同步数据', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _familyIdController,
                      decoration: const InputDecoration(
                        hintText: '例如：FAM-A3X9K2',
                        labelText: '家庭账号 ID',
                        prefixIcon: Icon(Icons.vpn_key_outlined),
                      ),
                      textCapitalization: TextCapitalization.characters,
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: '密码',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _loginWithFamilyId,
                        icon: const Icon(Icons.cloud_download),
                        label: const Text('登录并同步数据'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 分隔线
            Row(
              children: [
                Expanded(child: Divider(color: AppColors.textHint.withValues(alpha: 0.3))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('或', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ),
                Expanded(child: Divider(color: AppColors.textHint.withValues(alpha: 0.3))),
              ],
            ),
            const SizedBox(height: 20),

            // 方式二：本地文件导入
            _LoginOption(
              icon: Icons.folder_open,
              title: '本地 JSON 文件',
              subtitle: '选择设备上已有的家庭数据文件（纯本地，不联网）',
              onTap: _isLoading ? null : _loginFromFile,
            ),

            if (_isLoading) ...[
              const SizedBox(height: 32),
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(_loadingMessage, style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 使用家庭账号 ID + 密码登录
  Future<void> _loginWithFamilyId() async {
    final familyId = _familyIdController.text.trim().toUpperCase();
    final password = _passwordController.text;

    if (familyId.isEmpty) {
      setState(() => _error = '请输入家庭账号 ID');
      return;
    }
    if (!RegExp(r'^FAM-[A-Z0-9]{6}$').hasMatch(familyId)) {
      setState(() => _error = '账号格式不正确，应为 FAM- 开头加 6 位字母数字');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }

    setState(() { _isLoading = true; _error = null; _loadingMessage = '正在验证账号...'; });

    try {
      // 先从云端下载元信息验证密码
      setState(() => _loadingMessage = '正在验证密码...');
      final meta = await ref.read(autoSyncProvider).getRemoteMeta(familyId);

      if (meta == null) {
        setState(() { _isLoading = false; _error = '未找到该家庭账号的数据，请检查 ID 是否正确'; });
        return;
      }

      // 验证密码
      final storedHash = meta['passwordHash'] as String? ?? '';
      if (storedHash.isNotEmpty) {
        final inputHash = CryptoUtils.hashPassword(password, familyId);
        if (inputHash != storedHash) {
          setState(() { _isLoading = false; _error = '密码错误，请重新输入'; });
          return;
        }
      }

      // 密码验证通过，下载数据
      setState(() => _loadingMessage = '正在下载数据...');
      final success = await ref.read(autoSyncProvider).syncDown(familyId);

      if (!success) {
        setState(() { _isLoading = false; _error = '数据下载失败，请检查网络连接'; });
        return;
      }

      // 保存登录状态
      await ref.read(familyIdProvider.notifier).setFamilyId(familyId);
      await ref.read(syncConfigProvider.notifier).setFamilyId(familyId);

      // 用当前输入的密码重新生成哈希并保存（确保一致性）
      final newHash = CryptoUtils.hashPassword(password, familyId);
      await ref.read(passwordHashProvider.notifier).setPasswordHash(newHash);

      // 注意：不在登录后立即 syncUp 全量数据，因为 importAll 刚写入的 API Key
      // 在某些平台（特别是 Web）可能还未刷盘，syncUp 的 exportAll 会读到空值覆盖云端数据。
      // Dashboard 的 triggerAutoSync 会在数据稳定后自动同步。

      final familyName = meta['familyName'] as String? ?? '我的家庭';
      ref.read(familyNameProvider.notifier).state = familyName;
      ref.read(isDemoModeProvider.notifier).state = false;
      (await SharedPreferences.getInstance()).setString('family_name', familyName);

      // 自动选择第一个成员作为当前角色（确保自动登录可用）
      final db = ref.read(databaseProvider);
      final members = await db.getAllMembers();
      if (members.isNotEmpty) {
        await ref.read(currentRoleProvider.notifier).setRole(members.first.id);
      }

      if (mounted) context.go('/dashboard');
    } catch (e) {
      setState(() { _isLoading = false; _error = '登录失败: $e'; });
    }
  }

  /// 从本地文件登录
  Future<void> _loginFromFile() async {
    setState(() { _isLoading = true; _error = null; _loadingMessage = '读取文件...'; });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) {
        setState(() => _isLoading = false);
        return;
      }

      setState(() => _loadingMessage = '导入数据...');

      final bytes = result.files.single.bytes!;
      final content = utf8.decode(bytes);
      final data = jsonDecode(content) as Map<String, dynamic>;

      final db = ref.read(databaseProvider);
      final serializer = DataSerializer(db);
      await serializer.importAll(data);

      final familyName = data['familyName'] as String? ?? '我的家庭';
      ref.read(familyNameProvider.notifier).state = familyName;
      ref.read(isDemoModeProvider.notifier).state = false;

      // 自动选择第一个成员
      final members = await db.getAllMembers();
      if (members.isNotEmpty) {
        await ref.read(currentRoleProvider.notifier).setRole(members.first.id);
      }

      if (mounted) context.go('/dashboard');
    } catch (e) {
      setState(() { _isLoading = false; _error = '登录失败: $e'; });
    }
  }
}

class _LoginOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _LoginOption({required this.icon, required this.title, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: AppColors.primary, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}
