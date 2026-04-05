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
  FamilyIdNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('family_id');
  }

  Future<void> setFamilyId(String familyId) async {
    state = familyId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('family_id', familyId);
  }

  Future<void> clearFamilyId() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('family_id');
  }
}

class CurrentRoleNotifier extends StateNotifier<String?> {
  CurrentRoleNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('current_role_id');
  }

  Future<void> setRole(String memberId) async {
    state = memberId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_role_id', memberId);
  }

  Future<void> clearRole() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_role_id');
  }
}
