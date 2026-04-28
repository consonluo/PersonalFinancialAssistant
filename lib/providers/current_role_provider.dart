import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 当前角色状态 Provider
/// 记录用户选择的身份角色 ID，持久化到 SharedPreferences
final currentRoleProvider =
    StateNotifierProvider<CurrentRoleNotifier, String?>((ref) {
  return CurrentRoleNotifier();
});

/// 当前家庭名称
final familyNameProvider = StateProvider<String>((ref) => '');

/// 是否是 Demo 模式
final isDemoModeProvider = StateProvider<bool>((ref) => false);

/// 家庭账号 ID（如 FAM-A3X9K2）
final familyIdProvider =
    StateNotifierProvider<FamilyIdNotifier, String?>((ref) {
  return FamilyIdNotifier();
});

class FamilyIdNotifier extends StateNotifier<String?> {
  bool _explicitlySet = false;

  FamilyIdNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_explicitlySet) {
      state = prefs.getString('family_id');
    }
  }

  Future<void> setFamilyId(String familyId) async {
    _explicitlySet = true;
    state = familyId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('family_id', familyId);
  }

  Future<void> clearFamilyId() async {
    _explicitlySet = true;
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('family_id');
  }
}

/// 自定义账号名（6位字母数字，可用于登录）
final accountNameProvider =
    StateNotifierProvider<AccountNameNotifier, String?>((ref) {
  return AccountNameNotifier();
});

class AccountNameNotifier extends StateNotifier<String?> {
  bool _explicitlySet = false;

  AccountNameNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_explicitlySet) {
      state = prefs.getString('account_name');
    }
  }

  Future<void> setAccountName(String name) async {
    _explicitlySet = true;
    state = name.toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('account_name', name.toUpperCase());
  }

  Future<void> clear() async {
    _explicitlySet = true;
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('account_name');
  }

  static bool isValidFormat(String name) {
    return RegExp(r'^[A-Za-z0-9]{6}$').hasMatch(name);
  }
}

class CurrentRoleNotifier extends StateNotifier<String?> {
  bool _explicitlySet = false;

  CurrentRoleNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_explicitlySet) {
      state = prefs.getString('current_role_id');
    }
  }

  Future<void> setRole(String memberId) async {
    _explicitlySet = true;
    state = memberId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_role_id', memberId);
  }

  Future<void> clearRole() async {
    _explicitlySet = true;
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_role_id');
  }
}
