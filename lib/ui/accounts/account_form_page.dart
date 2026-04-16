import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/database_provider.dart';
import '../../providers/family_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/current_role_provider.dart';
import '../../providers/account_provider.dart';
import '../../data/database/app_database.dart';

class AccountFormPage extends ConsumerStatefulWidget {
  final String? accountId;
  final String? memberId;
  const AccountFormPage({super.key, this.accountId, this.memberId});

  @override
  ConsumerState<AccountFormPage> createState() => _AccountFormPageState();
}

class _AccountFormPageState extends ConsumerState<AccountFormPage> {
  final _institutionController = TextEditingController();
  AccountType _type = AccountType.securities;
  String? _selectedMemberId;
  bool _isEdit = false;
  String? _editAccountId;

  @override
  void initState() {
    super.initState();
    _selectedMemberId = widget.memberId ?? ref.read(currentRoleProvider);
    if (widget.accountId != null) {
      _isEdit = true;
      _editAccountId = widget.accountId;
      _loadAccount();
    }
    // 如果 currentRole 还没加载出来，等待加载后自动选中第一个成员
    if (_selectedMemberId == null && !_isEdit) {
      _autoSelectMember();
    }
  }

  Future<void> _autoSelectMember() async {
    // 等 currentRoleProvider 异步加载
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    final role = ref.read(currentRoleProvider);
    if (role != null) {
      setState(() => _selectedMemberId = role);
      return;
    }
    // 如果还是没有，取成员列表第一个
    final members = ref.read(familyMembersProvider).valueOrNull ?? [];
    if (members.isNotEmpty) {
      setState(() => _selectedMemberId = members.first.id);
    }
  }

  Future<void> _loadAccount() async {
    final db = ref.read(databaseProvider);
    final acc = await db.getAccountById(widget.accountId!);
    if (acc != null && mounted) {
      setState(() {
        _institutionController.text = acc.institution;
        _selectedMemberId = acc.memberId;
        _type = AccountType.values.firstWhere(
            (e) => e.name == acc.type,
            orElse: () => AccountType.securities);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(familyMembersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑账户' : '添加账户'),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              onPressed: _deleteAccount,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 所属成员
            membersAsync.when(
              data: (members) {
                // 确保 value 在 items 中，否则设为 null
                final validValue = members.any((m) => m.id == _selectedMemberId) ? _selectedMemberId : null;
                // 如果没有有效选中且有成员，自动选第一个
                if (validValue == null && members.isNotEmpty && _selectedMemberId == null) {
                  Future.microtask(() => setState(() => _selectedMemberId = members.first.id));
                }
                return DropdownButtonFormField<String>(
                  value: validValue,
                  decoration: const InputDecoration(labelText: '所属成员'),
                  items: members.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))).toList(),
                  onChanged: (v) => setState(() => _selectedMemberId = v),
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('加载成员失败'),
            ),
            const SizedBox(height: 20),

            // 机构名称
            const Text('金融机构', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('输入或选择券商/银行名称', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            TextField(
              controller: _institutionController,
              decoration: const InputDecoration(
                hintText: '例如：富途证券、微众银行',
                prefixIcon: Icon(Icons.business, size: 20),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: ['富途证券', '微众银行', '东方财富', '天天基金', '招商银行'].map((inst) {
                final selected = _institutionController.text == inst;
                return ChoiceChip(
                  label: Text(inst, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppColors.textPrimary)),
                  selected: selected,
                  onSelected: (_) => setState(() => _institutionController.text = inst),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // 账户类型
            DropdownButtonFormField<AccountType>(
              value: _type,
              decoration: const InputDecoration(labelText: '账户类型'),
              items: AccountType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(),
              onChanged: (v) => setState(() => _type = v ?? AccountType.securities),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _save, child: const Text('保存')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final institution = _institutionController.text.trim();
    if (institution.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入机构名称')));
      return;
    }
    if (_selectedMemberId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择所属成员')));
      return;
    }

    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final accountName = '$institution ${_type.label}';

    if (_isEdit && _editAccountId != null) {
      await db.updateAccount(AccountsCompanion(
        id: Value(_editAccountId!),
        memberId: Value(_selectedMemberId!),
        name: Value(accountName),
        type: Value(_type.name),
        institution: Value(institution),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
    } else {
      await db.insertAccount(AccountsCompanion(
        id: Value(const Uuid().v4()),
        memberId: Value(_selectedMemberId!),
        name: Value(accountName),
        type: Value(_type.name),
        institution: Value(institution),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
    }
    ref.read(autoSyncProvider).triggerAutoSync();
    // 手动刷新账户列表（Web端 drift stream 可能不及时通知）
    ref.invalidate(allAccountsProvider);
    if (mounted) context.pop();
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账户'),
        content: const Text('删除账户将同时删除该账户下的所有持仓数据，确定删除？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm == true && _editAccountId != null) {
      final db = ref.read(databaseProvider);
      // 删除该账户下的所有持仓
      final holdings = await db.getHoldingsByAccount(_editAccountId!);
      for (final h in holdings) {
        await db.deleteHolding(h.id);
      }
      // 删除该账户下的所有定投计划
      final plans = await db.getInvestmentPlansByAccount(_editAccountId!);
      for (final p in plans) {
        await db.deleteInvestmentPlan(p.id);
      }
      await db.deleteAccount(_editAccountId!);
      // 立即同步（不用防抖，确保删除立刻上传到云端）
      try { await ref.read(autoSyncProvider).syncUp(); } catch (_) {}
      ref.invalidate(allAccountsProvider);
      if (mounted) context.pop();
    }
  }

  @override
  void dispose() {
    _institutionController.dispose();
    super.dispose();
  }
}
