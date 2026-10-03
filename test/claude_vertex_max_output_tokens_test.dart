import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';

/// 输出上限由模型规格决定，不由代码里的模型名名单决定。
///
/// 历史上本仓库有一张"按模型名查输出上限"的硬表（`claudeVertexMaxOutputTokens`），
/// 早已与请求路径脱钩、只剩测试引用它；上游也已改为读规格。该表与其护栏测试已删除，
/// 这里保留的是**真实路径**的行为：`max_tokens` 取自模型规格（`spec.maxOutput`）。
void main() {
  group('这条规则只在 Vertex 端点生效', () {
    test('官方 Anthropic 端点按模型规格发 max_tokens', () async {
      Map<String, dynamic>? requestBody;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      server.listen((request) async {
        requestBody =
            (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                .cast<String, dynamic>();
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'id': 'msg_1',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        );
        await request.response.close();
      });

      await ChatApiService.sendMessageStream(
        config: ProviderConfig(
          id: 'ClaudeOfficialMaxTokensTest',
          enabled: true,
          name: 'ClaudeOfficialMaxTokensTest',
          apiKey: 'test-key',
          baseUrl: 'http://${server.address.address}:${server.port}',
          providerType: ProviderKind.claude,
        ),
        modelId: 'claude-3-5-sonnet@20240620',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
        stream: false,
      ).toList();

      final body = requestBody;
      expect(body, isNotNull);
      // 现在按 ModelSpec 的模型上限发：claude-3-5-sonnet 的实际上限为 8192。
      expect(body!['max_tokens'], 8192);
    });
  });
}
