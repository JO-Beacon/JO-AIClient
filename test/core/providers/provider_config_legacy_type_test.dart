import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';

/// 没有 `providerType` 的老配置：DeepSeek 按地址判定协议——
/// `/anthropic` 走 Claude，其余走 OpenAI；名字不参与判定。
void main() {
  group('inferLegacyDeepSeekType', () {
    test('/anthropic 端点判为 Claude', () {
      expect(
        ProviderConfig.inferLegacyDeepSeekType(
          'https://api.deepseek.com/anthropic',
        ),
        ProviderKind.claude,
      );
      expect(
        ProviderConfig.inferLegacyDeepSeekType(
          'https://api.deepseek.com/anthropic/v1',
        ),
        ProviderKind.claude,
      );
    });

    test('其余 DeepSeek 地址判为 OpenAI', () {
      for (final url in [
        'https://api.deepseek.com/v1',
        'https://api.deepseek.com',
        'https://api.deepseek.com/v1/chat/completions',
      ]) {
        expect(
          ProviderConfig.inferLegacyDeepSeekType(url),
          ProviderKind.openai,
          reason: url,
        );
      }
    });

    test('非 DeepSeek 地址不表态', () {
      for (final url in [
        '',
        'https://api.openai.com/v1',
        'https://openrouter.ai/api/v1',
      ]) {
        expect(
          ProviderConfig.inferLegacyDeepSeekType(url),
          isNull,
          reason: url,
        );
      }
    });
  });

  test('旧备份没有类型时，DeepSeek 配置按地址得出协议', () {
    final anthropic = ProviderConfig.fromJson({
      'id': 'DeepSeek',
      'name': 'DeepSeek',
      'apiKey': 'k',
      'baseUrl': 'https://api.deepseek.com/anthropic',
    });
    expect(anthropic.providerType, ProviderKind.claude);

    final openAi = ProviderConfig.fromJson({
      'id': 'DeepSeek',
      'name': 'DeepSeek',
      'apiKey': 'k',
      'baseUrl': 'https://api.deepseek.com/v1',
    });
    expect(openAi.providerType, ProviderKind.openai);

    // 其他厂商没类型时保持原样（交给 classify）。
    final other = ProviderConfig.fromJson({
      'id': 'MyProxy',
      'name': 'MyProxy',
      'apiKey': 'k',
      'baseUrl': 'https://proxy.example.com/v1',
    });
    expect(other.providerType, isNull);
  });
}
