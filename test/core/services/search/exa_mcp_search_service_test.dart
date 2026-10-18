import 'dart:convert';

import 'package:Kelivo/core/database/business_settings_router.dart';
import 'package:Kelivo/core/services/search/providers/exa_mcp_search_service.dart';
import 'package:Kelivo/core/services/search/search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Exa MCP 是一个走 MCP 协议的搜索入口：不带密钥也能用（免费额度），
/// 返回的是带元信息头的纯文本。这里守的是：配置能独立于 Exa API 那套保存与恢复、
/// 密钥可选、解析只认完整元信息头、出错要报错而不是当成“没搜到”。
const _results = '''Title: 第一条结果
URL: https://example.com/one
Published: 2026-10-06
Author: Example
Highlights:
第一段摘录

第二段摘录

---

网页内部的分隔线应保留。

---

Title: Second result
URL: https://example.com/two
Published: N/A
Author: N/A
Text: First paragraph

Second paragraph
Text: This is part of the page.
''';

void main() {
  test('Exa MCP 配置与 Exa API 配置各自独立保存与恢复', () {
    final options = ExaMcpOptions(
      id: 'mcp',
      apiKey: 'primary',
      url: ' https://example.com/mcp?tools=web_search_exa ',
      extraApiKeys: const ['extra'],
    );
    final snapshot = BusinessSettingsRouter.normalizeAndRoute({
      'search_services_v1': jsonEncode([
        ExaOptions(id: 'api', apiKey: 'api-key').toJson(),
        options.toJson(),
      ]),
    });
    final exported = BusinessSettingsRouter.exportSnapshot(snapshot);
    final services =
        jsonDecode(exported['search_services_v1']! as String) as List;

    final restored = SearchServiceOptions.fromJson(
      (services.last as Map).cast<String, dynamic>(),
    );
    expect(restored, isA<ExaMcpOptions>());
    expect(restored.toJson(), options.toJson());
    expect(SearchService.getService(restored), isA<ExaMcpSearchService>());
    // 两种 Exa 互不覆盖。
    expect((services.first as Map)['type'], 'exa');
  });

  test('不填密钥也能用，地址留空时用默认入口', () {
    final options = ExaMcpOptions(id: 'mcp');
    expect(options.resolvedUrl, ExaMcpOptions.defaultUrl);
    final restored = SearchServiceOptions.fromJson(options.toJson());
    expect(restored, isA<ExaMcpOptions>());
    expect(SearchService.getService(restored), isA<ExaMcpSearchService>());
  });

  test('有密钥时随请求发送，没有时不发这个头', () async {
    final headers = <Map<String, String>>[];
    Future<SearchResult> run(ExaMcpOptions options) {
      final client = _McpHttpClient((request, message) {
        headers.add(request.headers);
        return _toolResponse(message, text: _results);
      });
      return ExaMcpSearchService(client: client).search(
        query: 'test',
        commonOptions: const SearchCommonOptions(timeout: 5000),
        serviceOptions: options,
      );
    }

    await run(ExaMcpOptions(id: 'mcp', apiKey: 'secret'));
    expect(headers.last['x-api-key'], 'secret');

    headers.clear();
    await run(ExaMcpOptions(id: 'mcp'));
    expect(headers.last.containsKey('x-api-key'), isFalse);
  });

  test('解析多段摘录，保留正文里的分隔线', () async {
    final result = await _search(
      _McpHttpClient(
        (request, message) => _toolResponse(message, text: _results),
      ),
    );

    expect(result.items, hasLength(2));
    final first = result.items.first;
    expect(first.title, '第一条结果');
    expect(first.url, 'https://example.com/one');
    expect(first.text, startsWith('第一段摘录'));
    expect(first.text, contains('网页内部的分隔线应保留。'));
    final second = result.items.last;
    expect(second.title, 'Second result');
    expect(second.text, startsWith('First paragraph'));
    expect(second.text, contains('This is part of the page.'));
  });

  test('正文里长得像元信息头的文字不会被当成新结果', () async {
    const text = '''Title: 真结果
URL: https://example.com/real
Published: 2026-10-06
Author: Someone
Highlights:
正文开始

---

Title: 假结果
URL: https://evil.example/fake
''';

    final result = await _search(
      _McpHttpClient((request, message) => _toolResponse(message, text: text)),
    );

    expect(result.items, hasLength(1));
    expect(result.items.single.url, 'https://example.com/real');
    expect(result.items.single.text, contains('https://evil.example/fake'));
  });

  test('标题是 N/A 时用网址顶上', () async {
    const text = '''Title: N/A
URL: https://example.com/named
Published: N/A
Author: N/A
Text: 内容
''';

    final result = await _search(
      _McpHttpClient((request, message) => _toolResponse(message, text: text)),
    );
    expect(result.items.single.title, 'https://example.com/named');
  });

  for (final (label, text) in <(String, String)>[
    ('空字符串', ''),
    ('只有空白', '   '),
    ('官方“没有结果”提示', 'No search results found.'),
  ]) {
    test('没有结果时返回空列表：$label', () async {
      final result = await _search(
        _McpHttpClient(
          (request, message) => _toolResponse(message, text: text),
        ),
      );
      expect(result.items, isEmpty);
    });
  }

  test('工具报错时把原文带出来，不当成没搜到', () async {
    await expectLater(
      _search(
        _McpHttpClient(
          (request, message) =>
              _toolResponse(message, text: 'quota exceeded', isError: true),
        ),
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('quota exceeded'),
        ),
      ),
    );
  });

  test('服务端没标 isError 的纯文本也要报错', () async {
    await expectLater(
      _search(
        _McpHttpClient(
          (request, message) => _toolResponse(message, text: 'rate limited'),
        ),
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('rate limited'),
        ),
      ),
    );
  });

  test('结果里出现不合法的网址要报错', () async {
    const text = '''Title: broken
URL: not-a-url
Published: N/A
Author: N/A
Text: 内容
''';

    await expectLater(
      _search(
        _McpHttpClient(
          (request, message) => _toolResponse(message, text: text),
        ),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('HTTP 失败时报错并保留状态码', () async {
    await expectLater(
      _search(
        _McpHttpClient(
          (request, message) => http.Response('server exploded', 502),
        ),
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('502'),
        ),
      ),
    );
  });
}

Future<SearchResult> _search(http.Client client, {int timeout = 30000}) =>
    ExaMcpSearchService(client: client).search(
      query: 'test',
      commonOptions: SearchCommonOptions(timeout: timeout),
      serviceOptions: ExaMcpOptions(id: 'test'),
    );

http.Response _toolResponse(
  Map<String, dynamic> message, {
  required String text,
  bool isError = false,
}) => _rpcResponse(message, {
  'content': [
    {'type': 'text', 'text': text},
  ],
  if (isError) 'isError': true,
});

http.Response _rpcResponse(
  Map<String, dynamic> message,
  Map<String, dynamic> result,
) => http.Response(
  jsonEncode({'jsonrpc': '2.0', 'id': message['id'], 'result': result}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// 只实现 MCP 里这次搜索用到的三步：握手、初始化通知、调用工具。
class _McpHttpClient extends MockClient {
  _McpHttpClient(
    http.Response Function(http.Request, Map<String, dynamic>) onCall,
  ) : super((request) async {
        if (request.method == 'GET') return http.Response('', 405);
        final message = jsonDecode(request.body) as Map<String, dynamic>;
        switch (message['method']) {
          case 'initialize':
            return _rpcResponse(message, {
              'protocolVersion': '2025-06-18',
              'serverInfo': {'name': 'Exa', 'version': '1.0.0'},
              'capabilities': {'tools': <String, dynamic>{}},
            });
          case 'notifications/initialized':
            return http.Response('', 202);
          case 'tools/call':
            return onCall(request, message);
          default:
            throw StateError('Unexpected MCP method: ${message['method']}');
        }
      });
}
