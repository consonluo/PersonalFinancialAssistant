import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;
import '../../core/constants/app_constants.dart';
import '../../providers/database_provider.dart';
import '../../data/database/app_database.dart';

class MemberFormPage extends ConsumerStatefulWidget {
  final String? memberId;
  const MemberFormPage({super.key, this.memberId});

  @override
  ConsumerState<MemberFormPage> createState() => _MemberFormPageState();
}

class _MemberFormPageState extends ConsumerState<MemberFormPage> {
  final _nameController = TextEditingController();
  FamilyRole _role = FamilyRole.owner;
  bool _isEdit = false;

  @override
  void initState() {
    super.initState();
    if (widget.memberId != null) {
      _isEdit = true;
      _loadMember();
    }
  }

  Future<void> _loadMember() async {
    final db = ref.read(databaseProvider);
    final m = await db.getMemberById(widget.memberId!);
    if (m != null) {
      _nameController.text = m.name;
      _role = FamilyRole.values.firstWhere((e) => e.name == m.role, orElse: () => FamilyRole.other);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '编辑成员' : '添加成员')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: '姓名')),
            const SizedBox(height: 16),
            DropdownButtonFormField<FamilyRole>(
              value: _role,
              decoration: const InputDecoration(labelText: '角色'),
              items: FamilyRole.values.map((r) => DropdownMenuItem(value: r, child: Text(r.label))).toList(),
              onChanged: (v) => setState(() => _role = v ?? FamilyRole.other),
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
    if (_nameController.text.trim().isEmpty) return;
    final db = ref.read(databaseProvider);
    final now = DateTime.now();

    if (_isEdit) {
      await db.updateMember(FamilyMembersCompanion(
        id: Value(widget.memberId!),
        name: Value(_nameController.text.trim()),
        role: Value(_role.name),
        updatedAt: Value(now),
      ));
    } else {
      await db.insertMember(FamilyMembersCompanion(
        id: Value(const Uuid().v4()),
        name: Value(_nameController.text.trim()),
        role: Value(_role.name),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
    }
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
