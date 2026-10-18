import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import '../search_service.dart';
import '../web_fetch.dart';

class AnySearchSearchService extends SearchService<AnySearchOptions>
    implements WebFetchCapable<AnySearchOptions> {
  AnySearchSearchService({super.client});

  @override
  String get name => 'AnySearch';

  @override
  Widget description(BuildContext context) => Text(
    AppLocalizations.of(context)!.searchProviderAnySearchDescription,
    style: const TextStyle(fontSize: 12),
  );

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required AnySearchOptions serviceOptions,
  }) async {
    try {
      final key = serviceOptions.effectiveApiKey(serviceOptions.apiKey).trim();
      final response = await withHttpClient(
        (client) => client
            .post(
              Uri.parse(serviceOptions.resolvedUrl),
              headers: {
                'Content-Type': 'application/json',
                if (key.isNotEmpty) 'Authorization': 'Bearer $key',
              },
              body: jsonEncode({
                'query': query,
                'max_results': commonOptions.resultSize.clamp(1, 20),
                'format': 'json',
              }),
            )
            .timeout(Duration(milliseconds: commonOptions.timeout)),
      );
      if (response.statusCode != 200) {
        throw Exception(
          'API request failed: ${response.statusCode} ${response.body}',
        );
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final data =
          (payload['data'] as Map?)?.cast<String, dynamic>() ?? payload;
      final results = (data['results'] as List?) ?? const <dynamic>[];
      return SearchResult(
        items: results.map((item) {
          final result = (item as Map).cast<String, dynamic>();
          return SearchResultItem(
            title: '${result['title'] ?? ''}',
            url: '${result['url'] ?? ''}',
            text: '${result['snippet'] ?? result['content'] ?? ''}',
          );
        }).toList(),
      );
    } catch (e) {
      throw Exception('AnySearch search failed: $e');
    }
  }

  @override
  Future<WebFetchPage> fetch({
    required String url,
    required SearchCommonOptions commonOptions,
    required AnySearchOptions serviceOptions,
  }) async {
    try {
      final apiKey = serviceOptions
          .effectiveApiKey(serviceOptions.apiKey)
          .trim();
      final endpoint = siblingFetchEndpoint(
        serviceOptions.resolvedUrl,
        searchPath: '/search',
        fetchPath: '/extract',
      );
      final data = await postFetchJson(
        Uri.parse(endpoint),
        headers: {if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey'},
        body: {'url': url},
        commonOptions: commonOptions,
      );
      if (data['code'] != 0) throw Exception(data['message'] ?? data['code']);
      final page = (data['data'] as Map).cast<String, dynamic>();
      return WebFetchPage(
        url: (page['url'] ?? url).toString(),
        title: (page['title'] ?? '').toString(),
        content: (page['content'] ?? '').toString(),
      );
    } catch (e) {
      throw Exception('AnySearch fetch failed: $e');
    }
  }
}
