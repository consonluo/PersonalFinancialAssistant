import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Web 端使用 fetch API + ReadableStream 实现真正的 SSE 流式输出
Stream<String> webFetchStream({
  required String url,
  required Map<String, String> headers,
  required String body,
  required String? Function(String jsonStr) extractDelta,
}) {
  final controller = StreamController<String>();

  _doFetch(url, headers, body, extractDelta, controller);

  return controller.stream;
}

Future<void> _doFetch(
  String url,
  Map<String, String> headers,
  String body,
  String? Function(String) extractDelta,
  StreamController<String> controller,
) async {
  try {
    final headersInit = web.Headers();
    for (final entry in headers.entries) {
      headersInit.append(entry.key, entry.value);
    }

    final request = web.RequestInit(
      method: 'POST',
      headers: headersInit,
      body: body.toJS,
    );

    final response = await web.window.fetch(url.toJS, request).toDart;

    if (!response.ok) {
      controller.addError('AI 服务异常 (${response.status})');
      await controller.close();
      return;
    }

    final readableStream = response.body;
    if (readableStream == null) {
      controller.addError('无响应数据');
      await controller.close();
      return;
    }

    final reader = readableStream.getReader() as web.ReadableStreamDefaultReader;
    // 使用 TextDecoder 的 stream 模式正确处理跨 chunk 的 UTF-8 多字节字符
    final textDecoder = web.TextDecoder();
    String buffer = '';

    while (true) {
      final result = await reader.read().toDart;
      if (result.done) break;

      final chunk = result.value;
      if (chunk == null) continue;

      // 使用 TextDecoder stream 模式解码
      // chunk 是 Uint8Array (JSUint8Array)，需要转为 AllowSharedBufferSource
      final jsChunk = chunk as JSUint8Array;
      final decoded = textDecoder.decode(jsChunk, web.TextDecodeOptions(stream: true));
      buffer += decoded;

      // 解析 SSE 行
      while (buffer.contains('\n')) {
        final idx = buffer.indexOf('\n');
        final line = buffer.substring(0, idx).trim();
        buffer = buffer.substring(idx + 1);

        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();
          if (data == '[DONE]') {
            await controller.close();
            return;
          }
          if (data.isEmpty) continue;

          final delta = extractDelta(data);
          if (delta != null && delta.isNotEmpty) {
            controller.add(delta);
          }
        }
      }
    }

    await controller.close();
  } catch (e) {
    controller.addError('流式请求失败: $e');
    await controller.close();
  }
}
