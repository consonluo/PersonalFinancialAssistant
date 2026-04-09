import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:webdav_client/webdav_client.dart' as webdav;
import '../../core/constants/app_constants.dart';
import '../../core/utils/crypto_utils.dart';
import '../database/app_database.dart';
import 'data_serializer.dart';

/// WebDAV 同步服务
/// - 原生端：使用 webdav_client 完整 WebDAV 协议
/// - Web 端：通过 CORS 代理用简单 HTTP GET/PUT 直接读写文件（避免 PROPFIND 等复杂方法）
class WebDavSyncService {
  final AppDatabase db;
  final String familyId;

  // 原生端使用的 webdav_client
  webdav.Client? _client;

  // Web 端使用的 Dio
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// Web 端代理 base URL
  static String get _webProxyBase {
    final base = Uri.base;
    return '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}/webdav-proxy';
  }

  /// Web 端 Basic Auth header
  static String get _webAuthHeader {
    final credentials = base64Encode(
        utf8.encode('${AppConstants.webdavUser}:${AppConstants.webdavPass}'));
    return 'Basic $credentials';
  }

  /// 家庭专属远程目录
  String get _familyDir => '${AppConstants.webdavBaseDir}$familyId/';

  /// 远程数据文件路径
  String get _remoteFilePath => '${_familyDir}data.json';

  /// 远程元信息文件路径
  String get _remoteMetaPath => '${_familyDir}meta.json';

  WebDavSyncService({required this.db, required this.familyId}) {
    if (!kIsWeb) {
      _client = webdav.newClient(
        AppConstants.webdavUrl,
        user: AppConstants.webdavUser,
        password: AppConstants.webdavPass,
      );
      _client!.setHeaders({'accept-charset': 'utf-8'});
    }
  }

  // ===== Web 端简单 HTTP 方法 =====

  Future<List<int>?> _webRead(String remotePath) async {
    try {
      final url = '$_webProxyBase$remotePath';
      debugPrint('[WebDAV-Web] GET $url');
      final resp = await _dio.get<List<int>>(url,
          options: Options(
            headers: {'Authorization': _webAuthHeader},
            responseType: ResponseType.bytes,
          ));
      if (resp.statusCode == 200) return resp.data;
      debugPrint('[WebDAV-Web] GET failed: ${resp.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[WebDAV-Web] GET error: $e');
      return null;
    }
  }

  Future<bool> _webWrite(String remotePath, List<int> data) async {
    try {
      final url = '$_webProxyBase$remotePath';
      debugPrint('[WebDAV-Web] PUT $url (${data.length} bytes)');
      final resp = await _dio.put(url,
          data: Stream.fromIterable([data]),
          options: Options(
            headers: {
              'Authorization': _webAuthHeader,
              'Content-Type': 'application/octet-stream',
              'Content-Length': data.length,
            },
          ));
      final ok = resp.statusCode == 200 ||
          resp.statusCode == 201 ||
          resp.statusCode == 204;
      if (!ok) debugPrint('[WebDAV-Web] PUT failed: ${resp.statusCode}');
      return ok;
    } catch (e) {
      debugPrint('[WebDAV-Web] PUT error: $e');
      return false;
    }
  }

  Future<void> _webMkdir(String remotePath) async {
    try {
      final url = '$_webProxyBase$remotePath';
      final resp = await _dio.request(url,
          options: Options(
            method: 'MKCOL',
            headers: {'Authorization': _webAuthHeader},
          ));
      debugPrint('[WebDAV-Web] MKCOL $remotePath -> ${resp.statusCode}');
    } catch (_) {}
  }

  // ===== 公共接口 =====

  Future<bool> testConnection() async {
    if (kIsWeb) {
      final bytes = await _webRead(AppConstants.webdavBaseDir);
      return bytes != null;
    }
    try {
      await _client!.ping();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureDirs() async {
    if (kIsWeb) {
      await _webMkdir(AppConstants.webdavBaseDir);
      await _webMkdir(_familyDir);
      return;
    }
    try { await _client!.mkdir(AppConstants.webdavBaseDir); } catch (_) {}
    try { await _client!.mkdir(_familyDir); } catch (_) {}
  }

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
    if (kIsWeb) {
      await _webWrite(_remoteMetaPath, bytes);
      return;
    }
    await _client!.write(_remoteMetaPath, bytes);
  }

  Future<Map<String, dynamic>?> downloadMeta() async {
    try {
      List<int> bytes;
      if (kIsWeb) {
        final result = await _webRead(_remoteMetaPath);
        if (result == null) return null;
        bytes = result;
      } else {
        bytes = await _client!.read(_remoteMetaPath);
      }
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[WebDAV] downloadMeta error: $e');
      return null;
    }
  }

  Future<void> upload(String familyName) async {
    await _ensureDirs();
    final serializer = DataSerializer(db);
    final jsonStr = await serializer.exportToJsonString(familyName);
    final encrypted = CryptoUtils.encryptData(jsonStr, familyId);
    final bytes = utf8.encode(encrypted);
    if (kIsWeb) {
      await _webWrite(_remoteFilePath, bytes);
      return;
    }
    await _client!.write(_remoteFilePath, bytes);
  }

  Future<Map<String, dynamic>?> download() async {
    try {
      List<int> bytes;
      if (kIsWeb) {
        final result = await _webRead(_remoteFilePath);
        if (result == null) return null;
        bytes = result;
      } else {
        bytes = await _client!.read(_remoteFilePath);
      }
      final encrypted = utf8.decode(bytes);
      final jsonStr = CryptoUtils.decryptData(encrypted, familyId);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[WebDAV] download error: $e');
      return null;
    }
  }

  Future<void> syncUp(String familyName, {String? passwordHash}) async {
    await upload(familyName);
    if (passwordHash != null && passwordHash.isNotEmpty) {
      await uploadMeta(familyName: familyName, passwordHash: passwordHash);
    } else {
      final existingMeta = await downloadMeta();
      final existingHash = existingMeta?['passwordHash'] as String? ?? '';
      await uploadMeta(familyName: familyName, passwordHash: existingHash);
    }
  }

  Future<bool> syncDown() async {
    final data = await download();
    if (data == null) return false;
    final serializer = DataSerializer(db);
    await serializer.importAll(data);
    return true;
  }

  Future<bool> exists() async {
    if (kIsWeb) {
      final bytes = await _webRead(_remoteFilePath);
      return bytes != null;
    }
    try {
      final files = await _client!.readDir(_familyDir);
      return files.any((f) => f.name == 'data.json');
    } catch (_) {
      return false;
    }
  }
}
