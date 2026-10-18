import 'dart:convert';

import 'package:Kelivo/core/services/search/providers/bing_search_service.dart';
import 'package:Kelivo/core/services/search/search_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Bing 的网页搜索会用请求参数与请求头来判断“你是哪个地区的用户”。
/// 这里守的是：查询语句一字不改地发出去；地区只按界面语言取；
/// 结果链接要还原成真实地址；解析不了时明确报错，不要静默返回空结果。
const _oneResult = '''
  <ol id="b_results">
    <li class="b_algo">
      <h2><a href="https://flutter.dev/">Flutter</a></h2>
      <p>Build apps.</p>
    </li>
  </ol>
''';

Future<SearchResult> _searchHtml(
  String html, {
  int resultSize = 10,
  Locale locale = const Locale('en', 'US'),
}) {
  return BingSearchService(
    locale: locale,
    client: MockClient(
      (_) async => http.Response(
        html,
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      ),
    ),
  ).search(
    query: 'Flutter SelectionArea 复制',
    commonOptions: SearchCommonOptions(resultSize: resultSize),
    serviceOptions: const BingLocalOptions(id: 'bing'),
  );
}

String _trackingUrl(String target) {
  final encoded = base64Url.encode(utf8.encode(target)).replaceAll('=', '');
  return 'https://www.bing.com/ck/a?u=a1$encoded';
}

void main() {
  test('工厂会把界面语言交给服务，选项里不再保存语言设置', () {
    const options = BingLocalOptions(id: 'bing');
    final restored = SearchServiceOptions.fromJson(options.toJson());
    expect(restored, isA<BingLocalOptions>());
    expect(restored.toJson(), {'id': 'bing', 'type': 'bing_local'});

    final service = SearchService.getService(
      restored,
      locale: const Locale('de', 'DE'),
    );
    expect(service, isA<BingSearchService>());
    expect((service as BingSearchService).locale, const Locale('de', 'DE'));
  });

  test('查询语句原样发出，并按语言带上地区参数', () async {
    const query = 'Flutter SelectionArea 复制 + C++ & "copy"';
    late http.Request captured;
    final service = BingSearchService(
      locale: const Locale('de', 'DE'),
      client: MockClient((request) async {
        captured = request;
        return http.Response(_oneResult, 200);
      }),
    );

    await service.search(
      query: query,
      commonOptions: const SearchCommonOptions(resultSize: 5),
      serviceOptions: const BingLocalOptions(id: 'bing'),
    );

    expect(captured.method, 'GET');
    expect(captured.url.host, 'www.bing.com');
    expect(captured.url.path, '/search');
    expect(captured.url.queryParameters['q'], query);
    expect(captured.url.queryParameters['adlt'], 'moderate');
    expect(captured.url.queryParameters['setlang'], 'de');
    expect(captured.url.queryParameters['cc'], 'de');
    expect(captured.headers['Accept-Language'], 'de,de-DE;q=0.7,en;q=0.3');
    expect(captured.headers['Sec-Fetch-Mode'], 'navigate');
  });

  for (final (locale, setlang, cc) in <(Locale, String, String?)>[
    (const Locale('en', 'US'), 'en', null),
    (const Locale('zh', 'CN'), 'zh', null),
    (const Locale('zh', 'TW'), 'zh', 'tw'),
    (
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      'zh',
      'tw',
    ),
    (const Locale('zh', 'HK'), 'en', 'hk'),
    (const Locale('ja', 'JP'), 'ja', 'jp'),
  ]) {
    test('${locale.toLanguageTag()} 的地区参数为 setlang=$setlang cc=$cc', () async {
      late Uri uri;
      final service = BingSearchService(
        locale: locale,
        client: MockClient((request) async {
          uri = request.url;
          return http.Response(_oneResult, 200);
        }),
      );

      await service.search(
        query: 'x',
        commonOptions: const SearchCommonOptions(resultSize: 5),
        serviceOptions: const BingLocalOptions(id: 'bing'),
      );

      expect(uri.queryParameters['setlang'], setlang);
      expect(uri.queryParameters['cc'], cc);
    });
  }

  test('摘要合并多段、去掉装饰标签，并把跳转链接还原成真实地址', () async {
    final result = await _searchHtml('''
      <ol id="b_results">
        <li class="b_algo">
          <h2><a href="${_trackingUrl('https://example.com/a?x=1&y=2')}">Title A</a></h2>
          <span class="algoSlug_icon">Web</span>
          <p>First part<br>second part</p>
          <p>third part</p>
        </li>
      </ol>
    ''');

    expect(result.items, hasLength(1));
    final item = result.items.single;
    expect(item.title, 'Title A');
    expect(item.url, 'https://example.com/a?x=1&y=2');
    expect(item.text, 'First part second part third part');
  });

  test('没有段落的摘要退回备用选择器', () async {
    final result = await _searchHtml('''
      <ol id="b_results">
        <li class="b_algo">
          <h2><a href="https://example.com/b">Title B</a></h2>
          <div class="b_algoSlug">Only slug text</div>
        </li>
      </ol>
    ''');

    expect(result.items.single.text, 'Only slug text');
  });

  test('跳过无效与重复的条目，再按条数截断', () async {
    final result = await _searchHtml('''
      <ol id="b_results">
        <li class="b_algo"><h2>No link</h2><p>x</p></li>
        <li class="b_algo"><h2><a href="https://example.com/dup">Dup</a></h2></li>
        <li class="b_algo"><h2><a href="https://example.com/other">Other</a></h2></li>
        <li class="b_algo"><h2><a href="">Empty</a></h2></li>
      </ol>
    ''', resultSize: 2);

    expect(result.items.map((item) => item.title), ['Dup', 'Other']);
  });

  test('只有空标题的条目不会被当成结果返回', () async {
    // 这类条目会被跳过；跳完一条不剩、又没有“无结果”标记，
    // 于是按“页面无法识别”报错，而不是返回一条空标题的结果。
    await expectLater(
      _searchHtml('''
      <ol id="b_results">
        <li class="b_algo"><h2><a href="https://example.com/x">   </a></h2></li>
      </ol>
    '''),
      throwsA(isA<Exception>()),
    );
  });

  test('明确的“没有结果”页面返回空列表', () async {
    final result = await _searchHtml(
      '<ol id="b_results"><li class="b_no">没有找到结果</li></ol>',
    );
    expect(result.items, isEmpty);
  });

  test('无法识别的页面要报错，不能悄悄返回空结果', () async {
    await expectLater(
      _searchHtml('<html><body>unexpected</body></html>'),
      throwsA(isA<Exception>()),
    );
  });

  test('条数为 0 时根本不发请求', () async {
    var calls = 0;
    final service = BingSearchService(
      locale: const Locale('en', 'US'),
      client: MockClient((_) async {
        calls++;
        return http.Response(_oneResult, 200);
      }),
    );

    final result = await service.search(
      query: 'x',
      commonOptions: const SearchCommonOptions(resultSize: 0),
      serviceOptions: const BingLocalOptions(id: 'bing'),
    );

    expect(calls, 0);
    expect(result.items, isEmpty);
  });

  test('HTTP 失败要报错', () async {
    final service = BingSearchService(
      locale: const Locale('en', 'US'),
      client: MockClient((_) async => http.Response('nope', 503)),
    );

    await expectLater(
      service.search(
        query: 'x',
        commonOptions: const SearchCommonOptions(resultSize: 5),
        serviceOptions: const BingLocalOptions(id: 'bing'),
      ),
      throwsA(isA<Exception>()),
    );
  });
}
