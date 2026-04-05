import 'dart:convert';
import 'package:webdav_client/webdav_client.dart' as webdav;
import '../../core/constants/app_constants.dart';
import '../../core/utils/crypto_utils.dart';
import '../database/app_database.dart';
import 'data_serializer.dart';

/// WebDAV 同步服务（使用预设配置，按家庭ID分目录，加密存储）
class WebDavSyncService {
  final AppDatabase db;
  final String familyId;
  late final webdav.Client _client;

  WebDavSyncService({required this.db, required this.familyId}) {
    _client = webdav.newClient(
      AppConstants.webdavUrl,
      user: AppConstants.webdavUser,
      password: AppConstants.webdavPass,
    );
    _client.setHeaders({'accept-charset': 'utf-8'});
  }

  /// 家庭专属远程目录
  String get _familyDir => '${AppConstants.webdavBaseDir}$familyId/';

  /// 远程数据文件路径
  String get _remoteFilePath => '${_familyDir}data.json';

  /// 远程元信息文件路径（存储密码哈希、家庭名称等）
  String get _remoteMetaPath => '${_familyDir}meta.json';

  /// 测试连接
  Future<bool> testConnection() async {
    try {
      await _client.ping();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 确保远程目录结构存在
  Future<void> _ensureDirs() async {
    try {
      await _client.mkdir(AppConstants.webdavBaseDir);
    } catch (_) {}
    try {
      await _client.mkdir(_familyDir);
    } catch (_) {}
  }

  /// 上传元信息（密码哈希、家庭名称）
  Future<void> uploadMeta({
    required String familyName,
    required String passwordHash,
  }) async {
    await _ensureDirs();
    final meta = {
      'familyId': familyId,
      'familyName': familyName,
      'passwordHash': passwordHash,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    final bytes = utf8.encode(jsonEncode(meta));
    await _client.write(_remoteMetaPath, bytes);
  }

  /// 下载元信息
  Future<Map<String, dynamic>?> downloadMeta() async {
    try {
      final bytes = await _client.read(_remoteMetaPath);
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 上传数据到 WebDAV（加密）
  Future<void> upload(String familyName) async {
    await _ensureDirs();
    final serializer = DataSerializer(db);
    final jsonStr = await serializer.exportToJsonString(familyName);
    final encrypted = CryptoUtils.encryptData(jsonStr, familyId);
    final bytes = utf8.encode(encrypted);
    await _client.write(_remoteFilePath, bytes);
  }

  /// 从 WebDAV 下载并解密数据
  Future<Map<String, dynamic>?> download() async {
    try {
      final bytes = await _client.read(_remoteFilePath);
      final encrypted = utf8.decode(bytes);
      final jsonStr = CryptoUtils.decryptData(encrypted, familyId);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 同步上传（数据+元信息）
  Future<void> syncUp(String familyName, {String? passwordHash}) async {
    await upload(familyName);
    // 始终确保 meta.json 存在
    if (passwordHash != null && passwordHash.isNotEmpty) {
      // 有新密码哈希，直接上传
      await uploadMeta(familyName: familyName, passwordHash: passwordHash);
    } else {
      // 尝试读取已有的元信息保留密码哈希
      final existingMeta = await downloadMeta();
      final existingHash = existingMeta?['passwordHash'] as String? ?? '';
      // 无论如何都上传 meta（保证 meta.json 存在）
      await uploadMeta(familyName: familyName, passwordHash: existingHash);
    }
  }

  /// 同步下载并导入
  Future<bool> syncDown() async {
    final data = await download();
    if (data == null) return false;
    final serializer = DataSerializer(db);
    await serializer.importAll(data);
    return true;
  }

  /// 检查远程是否存在该家庭的数据
  Future<bool> exists() async {
    try {
      final files = await _client.readDir(_familyDir);
      return files.any((f) => f.name == 'data.json');
    } catch (_) {
      return false;
    }
  }
}
