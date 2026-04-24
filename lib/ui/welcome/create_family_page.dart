import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/crypto_utils.dart';
import '../../providers/database_provider.dart';
import '../../providers/current_role_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/family_provider.dart';
import '../../data/database/app_database.dart';

class CreateFamilyPage extends ConsumerStatefulWidget {
  const CreateFamilyPage({super.key});

  @override
  ConsumerState<CreateFamilyPage> createState() => _CreateFamilyPageState();
}

class _CreateFamilyPageState extends ConsumerState<CreateFamilyPage> {
  final _familyNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _members = <_MemberInput>[_MemberInput()];
  bool _isCreating = false;
  String _statusMessage = '';
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _localOnly = false;
  String? _accountNameError;

  @override
  void dispose() {
    _familyNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _accountNameController.dispose();
    super.dispose();
  }

  String _generateFamilyId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final code = List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
    return 'FAM-$code';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新建家庭'),
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
            const Text('家庭名称', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _familyNameController,
              decoration: const InputDecoration(hintText: '例如：张家、王氏大家庭'),
            ),
            const SizedBox(height: 20),

            // 本地/云同步切换
            Card(
              margin: EdgeInsets.zero,
              child: SwitchListTile(
                title: Text(_localOnly ? '仅本地使用' : '多设备云同步', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  _localOnly ? '数据仅保存在本设备，无需密码' : '数据自动同步到云端，可在多台设备使用',
                  style: const TextStyle(fontSize: 12),
                ),
                secondary: Icon(_localOnly ? Icons.phone_android : Icons.cloud_sync, color: AppColors.primary),
                value: !_localOnly,
                activeColor: AppColors.primary,
                onChanged: (v) => setState(() => _localOnly = !v),
              ),
            ),
            const SizedBox(height: 16),

            if (!_localOnly) ...[
              const Text('自定义账号名', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('6位字母或数字组合，可用于登录（选填）',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              TextField(
                controller: _accountNameController,
                decoration: InputDecoration(
                  hintText: '如 abc123',
                  errorText: _accountNameError,
                  counterText: '${_accountNameController.text.length}/6',
                ),
                maxLength: 6,
                textCapitalization: TextCapitalization.characters,
                onChanged: (v) {
                  setState(() {
                    _accountNameError = null;
                    if (v.isNotEmpty && !RegExp(r'^[A-Za-z0-9]*$').hasMatch(v)) {
                      _accountNameError = '只能包含字母和数字';
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              const Text('设置密码', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('其他设备登录时需要输入密码', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: '设置登录密码（至少6位）',
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  hintText: '确认密码',
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, size: 20),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('家庭成员', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                TextButton.icon(
                  onPressed: () => setState(() => _members.add(_MemberInput())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('请添加所有需要管理资产的家庭成员', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            ...List.generate(_members.length, (i) => _buildMemberRow(i)),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isCreating ? null : _createFamily,
                child: _isCreating
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                          const SizedBox(width: 12),
                          Text(_statusMessage.isEmpty ? '创建中...' : _statusMessage, style: const TextStyle(color: Colors.white)),
                        ],
                      )
                    : const Text('创建家庭'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberRow(int index) {
    final member = _members[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: member.nameController,
                decoration: InputDecoration(
                  hintText: index == 0 ? '例如：张三' : '例如：李四',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<FamilyRole>(
              value: member.role,
              items: FamilyRole.values.map((r) => DropdownMenuItem(
                value: r,
                child: Text(r.label, style: const TextStyle(fontSize: 14)),
              )).toList(),
              onChanged: (v) => setState(() => member.role = v ?? FamilyRole.other),
            ),
            if (_members.length > 1)
              IconButton(
                icon: const Icon(Icons.close, size: 20, color: AppColors.error),
                onPressed: () => setState(() => _members.removeAt(index)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _createFamily() async {
    final familyName = _familyNameController.text.trim();
    if (familyName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入家庭名称')));
      return;
    }

    if (!_localOnly) {
      final accountName = _accountNameController.text.trim();
      if (accountName.isNotEmpty) {
        if (!RegExp(r'^[A-Za-z0-9]{6}$').hasMatch(accountName)) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('账号名必须为6位字母或数字组合')));
          return;
        }
      }
      final password = _passwordController.text;
      if (password.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密码至少6位')));
        return;
      }
      if (password != _confirmPasswordController.text) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('两次密码不一致')));
        return;
      }
    }

    final validMembers = _members.where((m) => m.nameController.text.trim().isNotEmpty).toList();
    if (validMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请至少添加一位成员')));
      return;
    }

    setState(() { _isCreating = true; _statusMessage = '正在创建家庭...'; });

    try {
      final db = ref.read(databaseProvider);
      final uuid = const Uuid();
      final now = DateTime.now();

      await db.clearAllData();
      // 清除旧的用户配置（AI Key 等），避免新账号继承旧配置
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('zhipu_api_key');
      await prefs.remove('gemini_api_key');
      await prefs.remove('ai_provider');

      for (final m in validMembers) {
        await db.insertMember(FamilyMembersCompanion(
          id: Value(uuid.v4()),
          name: Value(m.nameController.text.trim()),
          role: Value(m.role.name),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
      }

      ref.read(familyNameProvider.notifier).state = familyName;
      ref.read(isDemoModeProvider.notifier).state = false;
      (await SharedPreferences.getInstance()).setString('family_name', familyName);

      // 设置 currentRole 为第一个成员（确保 Dashboard 有数据）
      final allMembers = await db.getAllMembers();
      if (allMembers.isNotEmpty) {
        await ref.read(currentRoleProvider.notifier).setRole(allMembers.first.id);
      }
      // 强制刷新数据源
      ref.invalidate(familyMembersProvider);

      if (_localOnly) {
        // 本地模式：生成 ID 但不设密码、不同步
        final familyId = _generateFamilyId();
        await ref.read(familyIdProvider.notifier).setFamilyId(familyId);

        if (!mounted) return;
        context.go('/dashboard');
      } else {
        // 云同步模式
        final familyId = _generateFamilyId();
        await ref.read(familyIdProvider.notifier).setFamilyId(familyId);
        await ref.read(syncConfigProvider.notifier).setFamilyId(familyId);

        final password = _passwordController.text;
        final passwordHash = CryptoUtils.hashPassword(password, familyId);
        await ref.read(passwordHashProvider.notifier).setPasswordHash(passwordHash);

        // 处理自定义账号名
        final accountName = _accountNameController.text.trim().toUpperCase();
        if (accountName.isNotEmpty) {
          setState(() => _statusMessage = '正在检查账号名...');
          final ok = await ref
              .read(autoSyncProvider)
              .setAccountName(accountName);
          if (!ok && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('账号名已被使用，请更换')),
            );
            setState(() {
              _isCreating = false;
              _statusMessage = '';
              _accountNameError = '该账号名已被使用';
            });
            return;
          }
        }

        setState(() => _statusMessage = '正在上传到云端...');
        await Future.delayed(const Duration(milliseconds: 500));
        bool syncOk = false;
        try {
          syncOk = await ref.read(autoSyncProvider).syncUp();
        } catch (_) {}

        if (!mounted) return;

        if (!syncOk) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('云端同步失败，其他设备暂时无法登录。请稍后在「设置 → 数据管理」中手动同步。'),
              duration: Duration(seconds: 5),
            ),
          );
        }

        if (!mounted) return;
        await _showFamilyIdDialog(familyId, accountName: accountName);
      }
    } catch (e) {
      setState(() { _isCreating = false; _statusMessage = ''; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e')));
      }
    }
  }

  Future<void> _showFamilyIdDialog(String familyId,
      {String accountName = ''}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.success, size: 28),
            SizedBox(width: 8),
            Text('家庭创建成功'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('您的家庭账号 ID 为：', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(familyId,
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          letterSpacing: 2)),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.copy,
                        size: 20, color: AppColors.primary),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: familyId));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('已复制到剪贴板')));
                    },
                  ),
                ],
              ),
            ),
            if (accountName.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('自定义账号名：$accountName',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('登录时可使用账号名代替家庭 ID',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber,
                      color: AppColors.warning, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      accountName.isNotEmpty
                          ? '请妥善保存账号名和密码！\n其他设备登录时输入账号名或 ID + 密码。'
                          : '请妥善保存此账号 ID 和密码！\n其他设备登录时需要输入账号 ID + 密码。',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/dashboard');
            },
            child: const Text('我已记住，继续'),
          ),
        ],
      ),
    );
  }
}

class _MemberInput {
  final TextEditingController nameController = TextEditingController();
  FamilyRole role = FamilyRole.owner;
}
