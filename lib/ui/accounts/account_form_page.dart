import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/database_provider.dart';
import '../../providers/family_provider.dart';
import '../../data/database/app_database.dart';

/// 常用机构
const _commonInstitutions = [
  '富途证券', '华泰证券', '中信证券', '中银证券', '国泰君安', '招商证券',
  '东方财富', '同花顺', '老虎证券', '长桥证券', '盈透证券',
  '微众银行', '招商银行', '工商银行', '建设银行', '中国银行', '农业银行',
  '天天基金', '蚂蚁财富', '理财通', '京东金融',
];

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

  @override
  void initState() {
    super.initState();
    _selectedMemberId = widget.memberId;
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(familyMembersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.accountId != null ? '编辑账户' : '添加账户')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 所属成员
            membersAsync.when(
              data: (members) => DropdownButtonFormField<String>(
                value: _selectedMemberId,
                decoration: const InputDecoration(labelText: '所属成员'),
                items: members.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))).toList(),
                onChanged: (v) => setState(() => _selectedMemberId = v),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('加载成员失败'),
            ),
            const SizedBox(height: 20),

            // 机构名称（唯一必填项）
            const Text('金融机构', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('输入或选择券商/银行名称', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Autocomplete<String>(
              optionsBuilder: (textEditingValue) {
                if (textEditingValue.text.isEmpty) return _commonInstitutions;
                return _commonInstitutions.where((i) => i.contains(textEditingValue.text));
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                // 同步到 _institutionController
                controller.addListener(() {
                  if (_institutionController.text != controller.text) {
                    _institutionController.text = controller.text;
                  }
                });
                if (controller.text.isEmpty && _institutionController.text.isNotEmpty) {
                  controller.text = _institutionController.text;
                }
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    hintText: '例如：富途证券、微众银行',
                    prefixIcon: Icon(Icons.business, size: 20),
                  ),
                );
              },
              onSelected: (v) => _institutionController.text = v,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: ['富途证券', '微众银行', '东方财富', '天天基金', '招商银行'].map((inst) {
                return ActionChip(
                  label: Text(inst, style: const TextStyle(fontSize: 12)),
                  onPressed: () => setState(() => _institutionController.text = inst),
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
    // 账户名称自动生成：机构名 + 账户类型
    final accountName = '$institution ${_type.label}';

    await db.insertAccount(AccountsCompanion(
      id: Value(const Uuid().v4()),
      memberId: Value(_selectedMemberId!),
      name: Value(accountName),
      type: Value(_type.name),
      institution: Value(institution),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    _institutionController.dispose();
    super.dispose();
  }
}
