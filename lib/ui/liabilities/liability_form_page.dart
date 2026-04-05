import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;
import '../../core/constants/app_constants.dart';
import '../../providers/database_provider.dart';
import '../../providers/family_provider.dart';
import '../../providers/sync_provider.dart';
import '../../data/database/app_database.dart';

class LiabilityFormPage extends ConsumerStatefulWidget {
  final String? liabilityId;
  final String? memberId;
  const LiabilityFormPage({super.key, this.liabilityId, this.memberId});

  @override
  ConsumerState<LiabilityFormPage> createState() => _LiabilityFormPageState();
}

class _LiabilityFormPageState extends ConsumerState<LiabilityFormPage> {
  final _nameController = TextEditingController();
  final _totalController = TextEditingController();
  final _remainingController = TextEditingController();
  final _rateController = TextEditingController();
  final _monthlyController = TextEditingController();
  LiabilityType _type = LiabilityType.mortgage;
  String? _selectedMemberId;
  bool _isEdit = false;

  @override
  void initState() {
    super.initState();
    _selectedMemberId = widget.memberId;
    if (widget.liabilityId != null) {
      _isEdit = true;
      _loadExisting();
    }
  }

  Future<void> _loadExisting() async {
    final db = ref.read(databaseProvider);
    final items = await db.getAllLiabilities();
    final existing = items.where((l) => l.id == widget.liabilityId).firstOrNull;
    if (existing != null) {
      setState(() {
        _nameController.text = existing.name;
        _totalController.text = existing.totalAmount.toStringAsFixed(2);
        _remainingController.text = existing.remainingAmount.toStringAsFixed(2);
        _rateController.text = existing.interestRate.toStringAsFixed(2);
        _monthlyController.text = existing.monthlyPayment.toStringAsFixed(2);
        _type = LiabilityType.values.firstWhere(
          (e) => e.name == existing.type,
          orElse: () => LiabilityType.other,
        );
        _selectedMemberId = existing.memberId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(familyMembersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '编辑负债' : '添加负债')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            membersAsync.when(
              data: (members) => DropdownButtonFormField<String>(
                value: _selectedMemberId,
                decoration: const InputDecoration(labelText: '所属成员'),
                items: members.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))).toList(),
                onChanged: (v) => setState(() => _selectedMemberId = v),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const SizedBox(),
            ),
            const SizedBox(height: 16),
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: '负债名称')),
            const SizedBox(height: 16),
            DropdownButtonFormField<LiabilityType>(
              value: _type,
              decoration: const InputDecoration(labelText: '类型'),
              items: LiabilityType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(),
              onChanged: (v) => setState(() => _type = v ?? LiabilityType.other),
            ),
            const SizedBox(height: 16),
            TextField(controller: _totalController, decoration: const InputDecoration(labelText: '总金额'), keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            TextField(controller: _remainingController, decoration: const InputDecoration(labelText: '剩余金额'), keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            TextField(controller: _rateController, decoration: const InputDecoration(labelText: '年化利率 %'), keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            TextField(controller: _monthlyController, decoration: const InputDecoration(labelText: '月还款额'), keyboardType: TextInputType.number),
            const SizedBox(height: 32),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _save, child: const Text('保存'))),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty || _selectedMemberId == null) return;
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final entry = LiabilitiesCompanion(
      id: Value(_isEdit ? widget.liabilityId! : const Uuid().v4()),
      memberId: Value(_selectedMemberId!),
      type: Value(_type.name),
      name: Value(_nameController.text.trim()),
      totalAmount: Value(double.tryParse(_totalController.text) ?? 0),
      remainingAmount: Value(double.tryParse(_remainingController.text) ?? 0),
      interestRate: Value(double.tryParse(_rateController.text) ?? 0),
      monthlyPayment: Value(double.tryParse(_monthlyController.text) ?? 0),
      createdAt: Value(now),
      updatedAt: Value(now),
    );

    if (_isEdit) {
      await db.updateLiability(entry);
    } else {
      await db.insertLiability(entry);
    }
    ref.read(autoSyncProvider).triggerAutoSync();
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _totalController.dispose();
    _remainingController.dispose();
    _rateController.dispose();
    _monthlyController.dispose();
    super.dispose();
  }
}
