import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';

/// 规格里的 `remoteImageUrls` 必须真的生效。
///
/// 曾经的实现只看"是不是 Kimi K3"，完全不读规格：于是模型编辑器里那个
/// "远程图片链接"开关被保存却从不生效——用户把它关掉，请求照旧把远程图片当图片发出去。
///
/// 要让这条测试有区分能力，必须让"改前"那条路真的走通：远程图片链接会被**实际校验**，
/// 因此这里由一个本地服务器返回一张真实 PNG，而不是用解析不了的域名
/// （那样改前改后都会回退成文本，测不出差别）。
const _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
    'q842iQAAAABJRU5ErkJggg==';

Future<Map<String, dynamic>> _sendOnce({
  required String modelId,
  required Map<String, dynamic> specOverride,
  required String userContent,
}) async {
  // 图片服务器：总是返回一张真实 PNG。
  final imageServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => imageServer.close(force: true));
  imageServer.listen((request) async {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType('image', 'png');
    request.response.add(base64Decode(_onePixelPngBase64));
    await request.response.close();
  });

  // 主服务器：捕获出站请求体。
  late Map<String, dynamic> body;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) async {
    body =
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    request.response.write(
      'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}\n\n',
    );
    request.response.write('data: [DONE]\n\n');
    await request.response.close();
  });

  final imageUrl =
      'http://${imageServer.address.address}:${imageServer.port}/x.png';

  await ChatApiService.sendMessageStream(
    config: ProviderConfig(
      id: 'RemoteImageUrlsTest',
      enabled: true,
      name: 'RemoteImageUrlsTest',
      apiKey: 'test-key',
      baseUrl: 'http://${server.address.address}:${server.port}/v1',
      providerType: ProviderKind.openai,
      models: [modelId],
      modelOverrides: {modelId: specOverride},
    ),
    modelId: modelId,
    messages: [
      {'role': 'user', 'content': '看图 ![a]($imageUrl) 谢谢'},
    ],
  ).toList();

  return body;
}

void main() {
  const baseSpec = <String, dynamic>{
    'type': 'chat',
    'input': ['text', 'image'],
    'output': ['text'],
  };

  test('规格声明接受远程图片时，远程图片按图片发出', () async {
    final body = await _sendOnce(
      modelId: 'remote-image-allowed',
      specOverride: {...baseSpec, 'remoteImageUrls': true},
      userContent: '',
    );

    // 对照组：确认这条链路真的会把远程图片变成图片内容。
    expect(jsonEncode(body['messages']).contains('image_url'), isTrue);
  });

  test('规格声明不接受远程图片时，链接只作为文本发出', () async {
    final body = await _sendOnce(
      modelId: 'remote-image-denied',
      specOverride: {...baseSpec, 'remoteImageUrls': false},
      userContent: '',
    );

    final serialized = jsonEncode(body['messages']);
    expect(
      serialized.contains('image_url'),
      isFalse,
      reason: '关掉远程图片链接后，不得把该链接当作图片发出',
    );
  });
}
