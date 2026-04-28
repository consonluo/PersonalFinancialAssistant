import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/sync_config_model.dart';
import '../data/sync/webdav_sync_service.dart';
import 'database_provider.dart';
import 'current_role_provider.dart';
import 'holding_provider.dart';
import 'account_provider.dart';
import 'family_provider.dart';
import 'liability_provider.dart';
import 'investment_plan_provider.dart';
import 'asset_summary_provider.dart';
import 'analysis_dimension_provider.dart';

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
  bool _explicitlySet = false;

  SyncConfigNotifier() : super(const SyncConfigModel()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (_explicitlySet) return;
    final jsonStr = prefs.getString('sync_config');
    if (jsonStr != null) {
      state = SyncConfigModel.fromJson(jsonDecode(jsonStr));
    }
  }

  Future<void> updateConfig(SyncConfigModel config) async {
    _explicitlySet = true;
    state = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync_config', jsonEncode(config.toJson()));
  }

  Future<void> setFamilyId(String familyId) async {
    final config = state.copyWith(familyId: familyId);
    await updateConfig(config);
  }

  Future<void> clearConfig() async {
    _explicitlySet = true;
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
  bool _explicitlySet = false;

  PasswordHashNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_explicitlySet) {
      state = prefs.getString('password_hash');
    }
  }

  Future<void> setPasswordHash(String hash) async {
    _explicitlySet = true;
    state = hash;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('password_hash', hash);
  }

  Future<void> clear() async {
    _explicitlySet = true;
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
  DateTime? _lastSyncDownTime;

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
    var familyId = _ref.read(familyIdProvider);
    var familyName = _ref.read(familyNameProvider);

    // 内存状态可能还没从 SharedPreferences 加载完，主动读取
    if (familyId == null || familyId.isEmpty || familyName.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      if (familyId == null || familyId.isEmpty) {
        familyId = prefs.getString('family_id');
        if (familyId != null && familyId.isNotEmpty) {
          await _ref.read(familyIdProvider.notifier).setFamilyId(familyId);
        }
      }
      if (familyName.isEmpty) {
        familyName = prefs.getString('family_name') ?? '';
        if (familyName.isNotEmpty) {
          _ref.read(familyNameProvider.notifier).state = familyName;
        }
      }
    }

    if (familyId == null || familyId.isEmpty) return false;
    if (familyName.isEmpty) return false;

    _ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;

    try {
      final db = _ref.read(databaseProvider);
      final passwordHash = _ref.read(passwordHashProvider);
      final accountName = _ref.read(accountNameProvider);
      final service = WebDavSyncService(db: db, familyId: familyId);
      await service.syncUp(familyName,
          passwordHash: passwordHash, accountName: accountName);

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
  ///
  /// [skipIfRecent] 为 true 时，若距上次 syncDown 不足 30 秒则跳过，
  /// 避免登录后 Dashboard 重复拉取导致数据闪清。
  Future<bool> syncDown(String familyId, {bool skipIfRecent = false}) async {
    if (skipIfRecent && _lastSyncDownTime != null) {
      final elapsed = DateTime.now().difference(_lastSyncDownTime!);
      if (elapsed.inSeconds < 30) {
        return true;
      }
    }

    _ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;

    try {
      final db = _ref.read(databaseProvider);
      final service = WebDavSyncService(db: db, familyId: familyId);
      final success = await service.syncDown();

      if (success) {
        _lastSyncDownTime = DateTime.now();
        _refreshAllDataProviders();
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

  /// 刷新所有数据相关的 Provider
  void _refreshAllDataProviders() {
    _ref.invalidate(allHoldingsProvider);
    _ref.invalidate(allAccountsProvider);
    _ref.invalidate(familyMembersProvider);
    _ref.invalidate(allLiabilitiesProvider);
    _ref.invalidate(allInvestmentPlansProvider);
    _ref.invalidate(assetSummaryProvider);
    _ref.invalidate(memberAssetProvider);
    _ref.invalidate(marketGroupProvider);
    _ref.invalidate(assetTypeGroupProvider);
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

  /// 检查账号名是否可用
  Future<bool> isAccountNameAvailable(String name) async {
    final familyId = _ref.read(familyIdProvider);
    if (familyId == null || familyId.isEmpty) return false;
    final db = _ref.read(databaseProvider);
    final service = WebDavSyncService(db: db, familyId: familyId);
    return service.isAccountNameAvailable(name);
  }

  /// 设置账号名（含唯一性校验、云端注册）
  Future<bool> setAccountName(String name, {String? oldName}) async {
    final familyId = _ref.read(familyIdProvider);
    if (familyId == null || familyId.isEmpty) return false;
    final db = _ref.read(databaseProvider);
    final service = WebDavSyncService(db: db, familyId: familyId);

    final available = await service.isAccountNameAvailable(name);
    if (!available) return false;

    if (oldName != null && oldName.isNotEmpty) {
      await service.unregisterAccountName(oldName);
    }
    final ok = await service.registerAccountName(name);
    if (ok) {
      await _ref.read(accountNameProvider.notifier).setAccountName(name);
      triggerAutoSync();
    }
    return ok;
  }

  /// 通过账号名查找 familyId
  Future<String?> lookupAccountName(String name) {
    return WebDavSyncService.lookupAccountName(name);
  }

  void dispose() {
    _debounceTimer?.cancel();
  }
}
