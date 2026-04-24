import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:webdav_client/webdav_client.dart' as webdav;
import '../../core/constants/app_constants.dart';
import '../../core/utils/crypto_utils.dart';
import '../database/app_database.dart';
import 'data_serializer.dart';

/// WebDAV 同步服务
/// - 原生端：webdav_client 完整 WebDAV 协议
/// - Web 端：Dio 直接 HTTP GET/PUT 通过 CORS 代理读写（不依赖 PROPFIND/MKCOL 等）
class WebDavSyncService {
  final AppDatabase db;
  final String familyId;

  // 原生端
  webdav.Client? _nativeClient;

  // Web 端 Dio（单例）
  static final Dio _webDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    validateStatus: (_) => true, // 不抛异常，手动判断状态码
  ));

  String get _familyDir => '${AppConstants.webdavBaseDir}$familyId/';
  String get _remoteFilePath => '${_familyDir}data.json';
  String get _remoteMetaPath => '${_familyDir}meta.json';

  /// Web 代理 base
  static String get _proxyBase {
    final b = Uri.base;
    return '${b.scheme}://${b.host}${b.hasPort ? ':${b.port}' : ''}/webdav-proxy';
  }

  /// Basic Auth
  static String get _basicAuth {
    final c = base64Encode(utf8.encode(
        '${AppConstants.webdavUser}:${AppConstants.webdavPass}'));
    return 'Basic $c';
  }

  WebDavSyncService({required this.db, required this.familyId}) {
    if (!kIsWeb) {
      _nativeClient = webdav.newClient(
        AppConstants.webdavUrl,
        user: AppConstants.webdavUser,
        password: AppConstants.webdavPass,
      );
      _nativeClient!.setHeaders({'accept-charset': 'utf-8'});
    }
  }

  // ========== Web 端 HTTP 工具 ==========

  /// GET 读取文件内容，返回字节数组
  Future<Uint8List?> _webGet(String remotePath) async {
    final url = '$_proxyBase$remotePath';
    debugPrint('[WebSync] GET $url');
    try {
      final resp = await _webDio.get<ResponseBody>(url,
          options: Options(
            headers: {'Authorization': _basicAuth},
            responseType: ResponseType.stream,
          ));
      if (resp.statusCode != 200 || resp.data == null) {
        debugPrint('[WebSync] GET $remotePath -> ${resp.statusCode}');
        return null;
      }
      // 收集 stream 数据
      final chunks = <int>[];
      await for (final chunk in resp.data!.stream) {
        chunks.addAll(chunk);
      }
      return Uint8List.fromList(chunks);
    } catch (e) {
      debugPrint('[WebSync] GET error: $e');
      return null;
    }
  }

  /// PUT 写入文件
  Future<bool> _webPut(String remotePath, Uint8List data) async {
    final url = '$_proxyBase$remotePath';
    debugPrint('[WebSync] PUT $url (${data.length} bytes)');
    try {
      final resp = await _webDio.put<dynamic>(url,
          data: data,
          options: Options(headers: {
            'Authorization': _basicAuth,
            'Content-Type': 'application/octet-stream',
          }));
      final ok = resp.statusCode == 200 ||
          resp.statusCode == 201 ||
          resp.statusCode == 204;
      if (!ok) debugPrint('[WebSync] PUT -> ${resp.statusCode}');
      return ok;
    } catch (e) {
      debugPrint('[WebSync] PUT error: $e');
      return false;
    }
  }

  /// 坚果云 WebDAV PUT 到不存在的路径时会自动创建父目录，无需 MKCOL

  // ========== 公共接口 ==========

  Future<bool> testConnection() async {
    if (kIsWeb) {
      // 简单 GET 根目录验证连通
      final r = await _webGet(AppConstants.webdavBaseDir);
      return r != null;
    }
    try {
      await _nativeClient!.ping();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Web 端 MKCOL 创建目录
  Future<void> _webMkcol(String remotePath) async {
    final url = '$_proxyBase$remotePath';
    debugPrint('[WebSync] MKCOL $url');
    try {
      await _webDio.request<dynamic>(url,
          options: Options(
            method: 'MKCOL',
            headers: {'Authorization': _basicAuth},
          ));
    } catch (_) {
      // 目录已存在返回 405/409 等，忽略
    }
  }

  Future<void> _ensureDirs() async {
    if (kIsWeb) {
      await _webMkcol(AppConstants.webdavBaseDir);
      await _webMkcol(_familyDir);
      return;
    }
    try { await _nativeClient!.mkdir(AppConstants.webdavBaseDir); } catch (_) {}
    try { await _nativeClient!.mkdir(_familyDir); } catch (_) {}
  }

  /// 上传元信息
  Future<void> uploadMeta({
    required String familyName,
    required String passwordHash,
    String? accountName,
  }) async {
    final meta = jsonEncode({
      'familyId': familyId,
      'familyName': familyName,
      'passwordHash': passwordHash,
      if (accountName != null && accountName.isNotEmpty)
        'accountName': accountName,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    final bytes = Uint8List.fromList(utf8.encode(meta));
    if (kIsWeb) {
      final ok = await _webPut(_remoteMetaPath, bytes);
      if (!ok) throw Exception('上传元信息失败');
      return;
    }
    await _ensureDirs();
    await _nativeClient!.write(_remoteMetaPath, bytes);
  }

  // ========== 账号名索引 ==========

  static String _nameIndexPath(String name) =>
      '${AppConstants.webdavBaseDir}_name_${name.toUpperCase()}.json';

  /// 检查账号名是否可用（不存在或属于当前家庭）
  Future<bool> isAccountNameAvailable(String name) async {
    final path = _nameIndexPath(name);
    try {
      Uint8List? bytes;
      if (kIsWeb) {
        bytes = await _webGet(path);
      } else {
        try {
          final raw = await _nativeClient!.read(path);
          bytes = Uint8List.fromList(raw);
        } catch (_) {
          bytes = null;
        }
      }
      if (bytes == null) return true;
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return data['familyId'] == familyId;
    } catch (_) {
      return true;
    }
  }

  /// 注册账号名索引
  Future<bool> registerAccountName(String name) async {
    final available = await isAccountNameAvailable(name);
    if (!available) return false;

    final path = _nameIndexPath(name);
    final content = jsonEncode({
      'familyId': familyId,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    final bytes = Uint8List.fromList(utf8.encode(content));

    if (kIsWeb) {
      return await _webPut(path, bytes);
    }
    await _ensureDirs();
    await _nativeClient!.write(path, bytes);
    return true;
  }

  /// 注销旧账号名索引
  Future<void> unregisterAccountName(String name) async {
    final path = _nameIndexPath(name);
    try {
      if (kIsWeb) {
        final url = '$_proxyBase$path';
        await _webDio.delete<dynamic>(url,
            options: Options(headers: {'Authorization': _basicAuth}));
      } else {
        await _nativeClient!.remove(path);
      }
    } catch (_) {}
  }

  /// 通过账号名查找 familyId
  static Future<String?> lookupAccountName(String name) async {
    final path = _nameIndexPath(name);
    try {
      if (kIsWeb) {
        final url = '$_proxyBase$path';
        final resp = await _webDio.get<ResponseBody>(url,
            options: Options(
              headers: {'Authorization': _basicAuth},
              responseType: ResponseType.stream,
            ));
        if (resp.statusCode != 200 || resp.data == null) return null;
        final chunks = <int>[];
        await for (final chunk in resp.data!.stream) {
          chunks.addAll(chunk);
        }
        final data = jsonDecode(utf8.decode(Uint8List.fromList(chunks)))
            as Map<String, dynamic>;
        return data['familyId'] as String?;
      } else {
        final client = webdav.newClient(
          AppConstants.webdavUrl,
          user: AppConstants.webdavUser,
          password: AppConstants.webdavPass,
        );
        final raw = await client.read(path);
        final data = jsonDecode(utf8.decode(Uint8List.fromList(raw)))
            as Map<String, dynamic>;
        return data['familyId'] as String?;
      }
    } catch (_) {
      return null;
    }
  }

  /// 下载元信息
  Future<Map<String, dynamic>?> downloadMeta() async {
    try {
      Uint8List bytes;
      if (kIsWeb) {
        final result = await _webGet(_remoteMetaPath);
        if (result == null) return null;
        bytes = result;
      } else {
        final raw = await _nativeClient!.read(_remoteMetaPath);
        bytes = Uint8List.fromList(raw);
      }
      final str = utf8.decode(bytes);
      debugPrint('[WebSync] meta content: $str');
      return jsonDecode(str) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[WebSync] downloadMeta error: $e');
      return null;
    }
  }

  /// 上传加密数据
  Future<void> upload(String familyName) async {
    final serializer = DataSerializer(db);
    final jsonStr = await serializer.exportToJsonString(familyName);
    final encrypted = CryptoUtils.encryptData(jsonStr, familyId);
    final bytes = Uint8List.fromList(utf8.encode(encrypted));
    await _ensureDirs();
    if (kIsWeb) {
      final ok = await _webPut(_remoteFilePath, bytes);
      if (!ok) throw Exception('上传数据失败');
      return;
    }
    await _nativeClient!.write(_remoteFilePath, bytes);
  }

  /// 下载并解密数据
  Future<Map<String, dynamic>?> download() async {
    try {
      Uint8List bytes;
      if (kIsWeb) {
        final result = await _webGet(_remoteFilePath);
        if (result == null) return null;
        bytes = result;
      } else {
        final raw = await _nativeClient!.read(_remoteFilePath);
        bytes = Uint8List.fromList(raw);
      }
      final encrypted = utf8.decode(bytes);
      final jsonStr = CryptoUtils.decryptData(encrypted, familyId);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[WebSync] download error: $e');
      return null;
    }
  }

  /// 同步上传（数据 + 元信息）
  Future<void> syncUp(String familyName,
      {String? passwordHash, String? accountName}) async {
    await upload(familyName);
    if (passwordHash != null && passwordHash.isNotEmpty) {
      await uploadMeta(
          familyName: familyName,
          passwordHash: passwordHash,
          accountName: accountName);
    } else {
      final existingMeta = await downloadMeta();
      final existingHash = existingMeta?['passwordHash'] as String? ?? '';
      await uploadMeta(
          familyName: familyName,
          passwordHash: existingHash,
          accountName: accountName);
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

  /// 检查远程数据是否存在
  Future<bool> exists() async {
    if (kIsWeb) {
      final bytes = await _webGet(_remoteFilePath);
      return bytes != null;
    }
    try {
      final files = await _nativeClient!.readDir(_familyDir);
      return files.any((f) => f.name == 'data.json');
    } catch (_) {
      return false;
    }
  }
}
