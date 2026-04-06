import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/database_provider.dart';
import '../../providers/account_provider.dart';
import '../../providers/sync_provider.dart';
import '../../data/database/app_database.dart';

class InvestmentPlanFormPage extends ConsumerStatefulWidget {
  final String? planId;
  const InvestmentPlanFormPage({super.key, this.planId});

  @override
  ConsumerState<InvestmentPlanFormPage> createState() => _InvestmentPlanFormPageState();
}

class _InvestmentPlanFormPageState extends ConsumerState<InvestmentPlanFormPage> {
  final _assetCodeController = TextEditingController();
  final _assetNameController = TextEditingController();
  final _amountController = TextEditingController();
  InvestFrequency _frequency = InvestFrequency.monthly;
  String? _selectedAccountId;
  bool _isActive = true;
  bool _isEdit = false;
  DateTime? _nextDate;

  @override
  void initState() {
    super.initState();
    if (widget.planId != null) {
      _isEdit = true;
      _loadExisting();
    }
  }

  Future<void> _loadExisting() async {
    final db = ref.read(databaseProvider);
    final plans = await db.getAllInvestmentPlans();
    final existing = plans.where((p) => p.id == widget.planId).firstOrNull;
    if (existing != null) {
      setState(() {
        _assetCodeController.text = existing.assetCode;
        _assetNameController.text = existing.assetName;
        _amountController.text = existing.amount.toStringAsFixed(2);
        _frequency = InvestFrequency.values.firstWhere(
          (f) => f.name == existing.frequency, orElse: () => InvestFrequency.monthly);
        _selectedAccountId = existing.accountId;
        _isActive = existing.isActive;
        _nextDate = existing.nextDate;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(allAccountsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '编辑定投计划' : '新建定投计划')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            accountsAsync.when(
              data: (accounts) => DropdownButtonFormField<String>(
                value: _selectedAccountId,
                decoration: const InputDecoration(labelText: '所属账户'),
                items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text('${a.name} · ${a.institution}'))).toList(),
                onChanged: (v) => setState(() => _selectedAccountId = v),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const SizedBox(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _assetCodeController,
              decoration: const InputDecoration(labelText: '标的代码', hintText: '如 161725、510300'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _assetNameController,
              decoration: const InputDecoration(labelText: '标的名称', hintText: '如 招商中证白酒'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(labelText: '每次定投金额', prefixText: '¥ '),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<InvestFrequency>(
              value: _frequency,
              decoration: const InputDecoration(labelText: '定投频率'),
              items: InvestFrequency.values.map((f) => DropdownMenuItem(value: f, child: Text(f.label))).toList(),
              onChanged: (v) => setState(() => _frequency = v ?? InvestFrequency.monthly),
            ),
            const SizedBox(height: 16),
            if (_isEdit)
              SwitchListTile(
                title: const Text('启用状态'),
                subtitle: Text(_isActive ? '运行中' : '已暂停'),
                value: _isActive,
                activeColor: AppColors.primary,
                onChanged: (v) => setState(() => _isActive = v),
                contentPadding: EdgeInsets.zero,
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
    if (_assetNameController.text.trim().isEmpty || _selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写完整信息')));
      return;
    }
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final entry = InvestmentPlansCompanion(
      id: Value(_isEdit ? widget.planId! : const Uuid().v4()),
      accountId: Value(_selectedAccountId!),
      assetCode: Value(_assetCodeController.text.trim()),
      assetName: Value(_assetNameController.text.trim()),
      amount: Value(double.tryParse(_amountController.text) ?? 0),
      frequency: Value(_frequency.name),
      nextDate: Value(_nextDate ?? now.add(const Duration(days: 1))),
      isActive: Value(_isActive),
      createdAt: Value(now),
    );

    if (_isEdit) {
      await db.updateInvestmentPlan(entry);
    } else {
      await db.insertInvestmentPlan(entry);
    }
    ref.read(autoSyncProvider).triggerAutoSync();
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    _assetCodeController.dispose();
    _assetNameController.dispose();
    _amountController.dispose();
    super.dispose();
  }
}
