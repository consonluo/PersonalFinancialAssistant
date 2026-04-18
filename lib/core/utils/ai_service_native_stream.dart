import 'dart:async';

/// 原生端不使用此实现（Dio stream 已够用），仅作为条件导入的 stub
Stream<String> webFetchStream({
  required String url,
  required Map<String, String> headers,
  required String body,
  required String? Function(String jsonStr) extractDelta,
}) {
  throw UnsupportedError('webFetchStream is only available on Web platform');
}
