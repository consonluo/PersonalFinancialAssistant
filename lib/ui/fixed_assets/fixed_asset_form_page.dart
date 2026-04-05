import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;
import '../../providers/database_provider.dart';
import '../../providers/family_provider.dart';
import '../../providers/sync_provider.dart';
import '../../data/database/app_database.dart';

class FixedAssetFormPage extends ConsumerStatefulWidget {
  final String? assetId;
  final String? memberId;
  const FixedAssetFormPage({super.key, this.assetId, this.memberId});

  @override
  ConsumerState<FixedAssetFormPage> createState() => _FixedAssetFormPageState();
}

class _FixedAssetFormPageState extends ConsumerState<FixedAssetFormPage> {
  final _nameController = TextEditingController();
  final _valueController = TextEditingController();
  final _notesController = TextEditingController();
  String _type = 'realEstate';
  String? _selectedMemberId;
  bool _isEdit = false;

  static const _typeOptions = [
    {'value': 'realEstate', 'label': '房产', 'icon': Icons.home},
    {'value': 'vehicle', 'label': '车辆', 'icon': Icons.directions_car},
    {'value': 'other', 'label': '其他', 'icon': Icons.category},
  ];

  @override
  void initState() {
    super.initState();
    _selectedMemberId = widget.memberId;
    if (widget.assetId != null) {
      _isEdit = true;
      _loadExisting();
    }
  }

  Future<void> _loadExisting() async {
    final db = ref.read(databaseProvider);
    final assets = await db.getAllFixedAssets();
    final existing = assets.where((a) => a.id == widget.assetId).firstOrNull;
    if (existing != null) {
      setState(() {
        _nameController.text = existing.name;
        _valueController.text = existing.estimatedValue.toStringAsFixed(2);
        _notesController.text = existing.notes;
        _type = existing.type;
        _selectedMemberId = existing.memberId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(familyMembersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '编辑资产' : '添加其他资产')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const Text('资产类型', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: _typeOptions.map((opt) {
                final selected = _type == opt['value'];
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(opt['icon'] as IconData, size: 16),
                          const SizedBox(width: 4),
                          Text(opt['label'] as String),
                        ],
                      ),
                      selected: selected,
                      onSelected: (_) => setState(() => _type = opt['value'] as String),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: '资产名称')),
            const SizedBox(height: 16),
            TextField(
              controller: _valueController,
              decoration: const InputDecoration(labelText: '估值金额', prefixText: '¥ '),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: '备注'),
              maxLines: 3,
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
    if (_nameController.text.trim().isEmpty || _selectedMemberId == null) return;
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final entry = FixedAssetsCompanion(
      id: Value(_isEdit ? widget.assetId! : const Uuid().v4()),
      memberId: Value(_selectedMemberId!),
      type: Value(_type),
      name: Value(_nameController.text.trim()),
      estimatedValue: Value(double.tryParse(_valueController.text) ?? 0),
      notes: Value(_notesController.text.trim()),
      createdAt: Value(now),
      updatedAt: Value(now),
    );

    if (_isEdit) {
      await db.updateFixedAsset(entry);
    } else {
      await db.insertFixedAsset(entry);
    }
    ref.read(autoSyncProvider).triggerAutoSync();
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}
