import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/sync_config_model.dart';
import '../data/sync/webdav_sync_service.dart';
import 'database_provider.dart';
import 'current_role_provider.dart';

/// 同步配置 Provider（简化版：只需 familyId）
final syncConfigProvider =
    StateNotifierProvider<SyncConfigNotifier, SyncConfigModel>((ref) {
  return SyncConfigNotifier();
});

/// 同步状态
final syncStatusProvider = StateProvider<SyncStatus>((ref) => SyncStatus.idle);

/// 上次同步时间
final lastSyncTimeProvider = StateProvider<DateTime?>((ref) => null);

enum SyncStatus { idle, syncing, success, error }

class SyncConfigNotifier extends StateNotifier<SyncConfigModel> {
  SyncConfigNotifier() : super(const SyncConfigModel()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('sync_config');
    if (jsonStr != null) {
      state = SyncConfigModel.fromJson(jsonDecode(jsonStr));
    }
  }

  Future<void> updateConfig(SyncConfigModel config) async {
    state = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync_config', jsonEncode(config.toJson()));
  }

  Future<void> setFamilyId(String familyId) async {
    final config = state.copyWith(familyId: familyId);
    await updateConfig(config);
  }

  Future<void> clearConfig() async {
    state = const SyncConfigModel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sync_config');
  }
}

/// 密码哈希持久化 Provider
final passwordHashProvider =
    StateNotifierProvider<PasswordHashNotifier, String?>((ref) {
  return PasswordHashNotifier();
});

class PasswordHashNotifier extends StateNotifier<String?> {
  PasswordHashNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('password_hash');
  }

  Future<void> setPasswordHash(String hash) async {
    state = hash;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('password_hash', hash);
  }

  Future<void> clear() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('password_hash');
  }
}

/// 自动同步管理器（使用预设WebDAV + familyId）
final autoSyncProvider = Provider<AutoSyncManager>((ref) {
  return AutoSyncManager(ref);
});

class AutoSyncManager {
  final Ref _ref;
  Timer? _debounceTimer;

  AutoSyncManager(this._ref);

  /// 触发自动上传同步（带防抖，数据变更后 3 秒执行）
  void triggerAutoSync() {
    final familyId = _ref.read(familyIdProvider);
    if (familyId == null || familyId.isEmpty) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 3), () {
      syncUp();
    });
  }

  /// 上传同步
  Future<bool> syncUp() async {
    final familyId = _ref.read(familyIdProvider);
    if (familyId == null || familyId.isEmpty) return false;

    final familyName = _ref.read(familyNameProvider);
    if (familyName.isEmpty) return false;

    _ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;

    try {
      final db = _ref.read(databaseProvider);
      final passwordHash = _ref.read(passwordHashProvider);
      final service = WebDavSyncService(db: db, familyId: familyId);
      await service.syncUp(familyName, passwordHash: passwordHash);

      final now = DateTime.now();
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
      _ref.read(lastSyncTimeProvider.notifier).state = now;

      await _ref.read(syncConfigProvider.notifier).updateConfig(
            SyncConfigModel(familyId: familyId, lastSyncTime: now),
          );
      return true;
    } catch (_) {
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      return false;
    }
  }

  /// 下载同步（通过家庭账号ID）
  Future<bool> syncDown(String familyId) async {
    _ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;

    try {
      final db = _ref.read(databaseProvider);
      final service = WebDavSyncService(db: db, familyId: familyId);
      final success = await service.syncDown();

      if (success) {
        _ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
        _ref.read(lastSyncTimeProvider.notifier).state = DateTime.now();
      } else {
        _ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      }
      return success;
    } catch (_) {
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      return false;
    }
  }

  /// 获取远程元信息（用于验证密码）
  Future<Map<String, dynamic>?> getRemoteMeta(String familyId) async {
    try {
      final db = _ref.read(databaseProvider);
      final service = WebDavSyncService(db: db, familyId: familyId);
      return await service.downloadMeta();
    } catch (_) {
      return null;
    }
  }

  /// 测试连接
  Future<bool> testConnection(String familyId) async {
    try {
      final db = _ref.read(databaseProvider);
      final service = WebDavSyncService(db: db, familyId: familyId);
      return await service.testConnection();
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
  }
}
