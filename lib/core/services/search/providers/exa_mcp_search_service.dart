import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mcp_client/mcp_client.dart' as mcp;

import '../../../../l10n/app_localizations.dart';
import '../../network/dio_http_client.dart';
import '../search_service.dart';
import '../web_fetch.dart';

/// 通过 MCP 协议使用 Exa 搜索：不带密钥也能在免费额度内用，
/// 带上密钥则走同一个入口。
class ExaMcpSearchService extends SearchService<ExaMcpOptions>
    implements WebFetchCapable<ExaMcpOptions> {
  ExaMcpSearchService({super.client});

  @override
  String get name => 'Exa MCP';

  @override
  Widget description(BuildContext context) => Text(
    AppLocalizations.of(context)!.searchProviderExaMcpDescription,
    style: const TextStyle(fontSize: 12),
  );

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required ExaMcpOptions serviceOptions,
  }) async {
    final limit = commonOptions.resultSize < 1 ? 1 : commonOptions.resultSize;
    try {
      final text = await _callTool(
        'web_search_exa',
        {'query': query, 'numResults': limit},
        commonOptions: commonOptions,
        serviceOptions: serviceOptions,
      );
      return SearchResult(items: _parseResults(text).take(limit).toList());
    } catch (error) {
      final detail = error is StateError ? error.message : error.toString();
      throw Exception('Exa MCP search failed: $detail');
    }
  }

  @override
  Future<WebFetchPage> fetch({
    required String url,
    required SearchCommonOptions commonOptions,
    required ExaMcpOptions serviceOptions,
  }) async {
    try {
      final text = await _callTool(
        'web_fetch_exa',
        {
          'urls': [url],
          'maxCharacters': webFetchMaxContentLength,
        },
        commonOptions: commonOptions,
        serviceOptions: serviceOptions,
      );
      return _parsePage(text);
    } catch (error) {
      final detail = error is StateError ? error.message : error.toString();
      throw Exception('Exa MCP fetch failed: $detail');
    }
  }

  /// 调用一个 Exa 托管的工具，返回它的文本内容。
  Future<String> _callTool(
    String tool,
    Map<String, dynamic> arguments, {
    required SearchCommonOptions commonOptions,
    required ExaMcpOptions serviceOptions,
  }) async {
    final timeout = Duration(milliseconds: commonOptions.timeout);
    final apiKey = serviceOptions.effectiveApiKey(serviceOptions.apiKey).trim();
    final cancellation = CancelToken();
    final ownsHttpClient = client == null;
    final httpClient = client ?? DioHttpClient(cancelToken: cancellation);

    try {
      final transport = await mcp.StreamableHttpClientTransport.create(
        baseUrl: serviceOptions.resolvedUrl,
        headers: {if (apiKey.isNotEmpty) 'x-api-key': apiKey},
        httpClient: _BorrowedHttpClient(httpClient),
        timeout: timeout,
        terminateOnClose: false,
      );
      final client = mcp.Client(
        name: 'Kelivo',
        version: '1.0.0',
        requestTimeout: timeout,
      );
      final elapsed = Stopwatch()..start();
      try {
        await client.connect(transport);
        final remaining = timeout - elapsed.elapsed;
        if (remaining <= Duration.zero) {
          throw TimeoutException('Exa MCP $tool timed out', timeout);
        }
        client.setRequestTimeout(remaining);
        final result = await client.callTool(tool, arguments);
        final text = result.content
            .whereType<mcp.TextContent>()
            .map((content) => content.text)
            .where((text) => text.trim().isNotEmpty)
            .join('\n\n---\n\n');
        if (result.isError == true) {
          throw StateError(
            text.trim().isEmpty ? 'Exa MCP tool failed' : text.trim(),
          );
        }
        return text;
      } finally {
        client.dispose();
        transport.close();
      }
    } finally {
      // DioHttpClient.close 只让请求不再生效，不会掐断进行中的请求。
      // 这个取消标记只属于本次调用，结束后顺手取消，卡住的连接才会释放。
      cancellation.cancel('Exa MCP $tool finished');
      if (ownsHttpClient) httpClient.close();
    }
  }

  /// 解析 `web_fetch_exa` 的输出：`# 标题`、一行 `URL:`，然后是正文。
  WebFetchPage _parsePage(String text) {
    final normalized = text.replaceAll('\r\n', '\n').trim();
    final header = RegExp(
      r'^#[ \t]*(.*)\nURL:[ \t]*(\S+)[ \t]*(?:\n|$)',
    ).firstMatch(normalized);
    if (header == null) {
      // 配额与抓取错误也以纯文本返回，且不置 isError。
      throw StateError(normalized.isEmpty ? 'no content returned' : normalized);
    }
    return WebFetchPage(
      url: header.group(2)!,
      title: header.group(1)!.trim(),
      content: normalized.substring(header.end).trim(),
    );
  }

  List<SearchResultItem> _parseResults(String text) {
    final normalized = text.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty ||
        normalized.startsWith('No search results found.')) {
      return [];
    }

    // 必须匹配 Exa 完整的元信息头：结果正文里本身就可能出现分隔线加
    // “Title:/URL:” 这样的示例文字，宽松匹配会把它们当成真结果。
    final headers = RegExp(
      r'(?:^|\n[ \t]*\n---[ \t]*\n[ \t]*\n)'
      r'Title:[ \t]*(.*)\nURL:[ \t]*(\S+)[ \t]*\n'
      r'Published:[^\n]*\nAuthor:[^\n]*(?=\n|$)',
    ).allMatches(normalized).toList();
    if (headers.isEmpty) {
      // 官方服务把配额错误也当纯文本返回，且不置 isError。
      // 这时要把原文抛出去，而不是当成“没有结果”。
      throw StateError(normalized);
    }

    final results = <SearchResultItem>[];
    for (var index = 0; index < headers.length; index++) {
      final header = headers[index];
      final url = header.group(2)!;
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.host.isEmpty ||
          (uri.scheme != 'https' && uri.scheme != 'http')) {
        throw const FormatException('Exa MCP returned an invalid result URL');
      }
      final hasNext = index + 1 < headers.length;
      final body = normalized.substring(
        header.end,
        hasNext ? headers[index + 1].start : normalized.length,
      );
      final marker = RegExp(
        r'^(?:Highlights|Text):[ \t]*',
        multiLine: true,
      ).firstMatch(body);
      final title = header.group(1)!.trim();
      results.add(
        SearchResultItem(
          title: title.isEmpty || title == 'N/A' ? url : title,
          url: url,
          text: marker == null ? '' : body.substring(marker.end).trim(),
        ),
      );
    }
    return results;
  }
}

// 传输层关闭时会连带关掉 HTTP 客户端；而这个客户端的所有权在搜索这一侧。
class _BorrowedHttpClient extends http.BaseClient {
  _BorrowedHttpClient(this.delegate);

  final http.Client delegate;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      delegate.send(request);
}
