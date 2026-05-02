import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
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

  /// 原生 WebDAV 无内置超时，网络异常时会长时间阻塞；用于避免启动页/界面卡死。
  static const Duration _syncUpTimeout = Duration(seconds: 60);
  static const Duration _syncDownTimeout = Duration(seconds: 45);

  /// 持久化在 SharedPreferences 中的标记，表示有未上传的本地变更。
  /// 防止 syncDown 在本地变更上传前覆盖本地数据库导致数据丢失。
  static const _kPendingSyncKey = 'pending_sync';

  AutoSyncManager(this._ref);

  /// 标记有未上传的本地变更（应在每次 insert/update/delete 后立即调用）
  static Future<void> markPendingSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPendingSyncKey, true);
  }

  static Future<bool> hasPendingSync() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPendingSyncKey) ?? false;
  }

  static Future<void> clearPendingSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPendingSyncKey, false);
  }

  /// 触发自动上传同步（带防抖，数据变更后 1.5 秒执行）
  /// 同时立即写入 pendingSync 标记，防止防抖期间被 syncDown 覆盖。
  void triggerAutoSync() {
    final familyId = _ref.read(familyIdProvider);
    if (familyId == null || familyId.isEmpty) return;

    // 立即标记 pending，以便此期间任何 syncDown 都会先把本地变更推上去
    markPendingSync();

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
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

      // 安全检查：本地持仓为空但云端可能有数据时，拒绝上传以防覆盖
      final holdings = await db.getAllHoldings();
      final members = await db.getAllMembers();
      if (holdings.isEmpty && members.isEmpty) {
        debugPrint('[Sync] syncUp aborted: local DB is empty, refusing to overwrite cloud data');
        _ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
        return false;
      }

      final passwordHash = _ref.read(passwordHashProvider);
      final accountName = _ref.read(accountNameProvider);
      final service = WebDavSyncService(db: db, familyId: familyId);
      await service
          .syncUp(
            familyName,
            passwordHash: passwordHash,
            accountName: accountName,
          )
          .timeout(_syncUpTimeout);

      final now = DateTime.now();
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
      _ref.read(lastSyncTimeProvider.notifier).state = now;

      await _ref.read(syncConfigProvider.notifier).updateConfig(
            SyncConfigModel(familyId: familyId, lastSyncTime: now),
          );
      // 上传成功后清除 pending 标记
      await clearPendingSync();
      return true;
    } on TimeoutException catch (e) {
      debugPrint('[Sync] syncUp timeout: $e');
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      return false;
    } catch (e) {
      debugPrint('[Sync] syncUp error: $e');
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      return false;
    }
  }

  /// 下载同步（通过家庭账号ID）
  ///
  /// [skipIfRecent] 为 true 时，若距上次 syncDown 不足 30 秒则跳过，
  /// 避免登录后 Dashboard 重复拉取导致数据闪清。
  ///
  /// 调用前会先检查 pendingSync 标记：若有未上传的本地变更，强制先 syncUp，
  /// 防止云端旧数据覆盖本地新增/修改/删除。
  Future<bool> syncDown(String familyId, {bool skipIfRecent = false}) async {
    if (skipIfRecent && _lastSyncDownTime != null) {
      final elapsed = DateTime.now().difference(_lastSyncDownTime!);
      if (elapsed.inSeconds < 30) {
        return true;
      }
    }

    // 关键：若有未上传的本地变更，先把它推上去，再拉云端
    if (await hasPendingSync()) {
      debugPrint('[Sync] syncDown: pending changes detected, force syncUp first');
      _debounceTimer?.cancel(); // 取消防抖立即上传
      final pushOk = await syncUp();
      if (!pushOk) {
        debugPrint('[Sync] syncDown: pre-syncUp failed, abort syncDown to avoid data loss');
        // 本地变更未能上传时，跳过 syncDown（保留本地状态）
        return false;
      }
    }

    _ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;

    try {
      final db = _ref.read(databaseProvider);
      final service = WebDavSyncService(db: db, familyId: familyId);
      final success = await service.syncDown().timeout(_syncDownTimeout);

      if (success) {
        _lastSyncDownTime = DateTime.now();
        _refreshAllDataProviders();
        _ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
        _ref.read(lastSyncTimeProvider.notifier).state = DateTime.now();
      } else {
        _ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      }
      return success;
    } on TimeoutException catch (e) {
      debugPrint('[Sync] syncDown timeout: $e');
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      return false;
    } catch (e) {
      debugPrint('[Sync] syncDown error: $e');
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
