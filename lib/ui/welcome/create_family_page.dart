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
  final _members = <_MemberInput>[_MemberInput()];
  bool _isCreating = false;
  String _statusMessage = '';
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _familyNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

    final password = _passwordController.text;
    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密码至少6位')));
      return;
    }
    if (password != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('两次密码不一致')));
      return;
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
      // 持久化家庭名称
      (await SharedPreferences.getInstance()).setString('family_name', familyName);

      // 生成家庭账号 ID
      final familyId = _generateFamilyId();
      await ref.read(familyIdProvider.notifier).setFamilyId(familyId);
      await ref.read(syncConfigProvider.notifier).setFamilyId(familyId);

      // 存储密码哈希
      final passwordHash = CryptoUtils.hashPassword(password, familyId);
      await ref.read(passwordHashProvider.notifier).setPasswordHash(passwordHash);

      // 自动上传到云端（含密码哈希）
      setState(() => _statusMessage = '正在上传到云端...');
      try {
        await ref.read(autoSyncProvider).syncUp();
      } catch (_) {}

      if (!mounted) return;

      // 展示家庭账号 ID
      await _showFamilyIdDialog(familyId);
    } catch (e) {
      setState(() { _isCreating = false; _statusMessage = ''; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e')));
      }
    }
  }

  Future<void> _showFamilyIdDialog(String familyId) async {
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
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(familyId, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: 2)),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20, color: AppColors.primary),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: familyId));
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, color: AppColors.warning, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '请妥善保存此账号 ID 和密码！\n其他设备登录时需要输入账号 ID + 密码。',
                      style: TextStyle(fontSize: 12, color: AppColors.warning),
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
