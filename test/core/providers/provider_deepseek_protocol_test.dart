import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/model_spec/vendor_defaults.dart';
import 'package:Kelivo/core/models/model_spec.dart';

/// DeepSeek 协议口径的回归锚点（所有者 2026-10-04 确认）：
/// 1. 预设与导入默认走 Claude（`/anthropic`），用户可显式改成 OpenAI；
/// 2. 名字不再参与推断；
/// 3. 没有显式类型的老配置按地址判：`/anthropic` → Claude，其余 → OpenAI。
///
/// 任何一条被改动，这里都会红。
void main() {
  test('名字不再猜协议：classify 把 DeepSeek 归为 OpenAI', () {
    expect(ProviderConfig.classify('DeepSeek'), ProviderKind.openai);
    expect(ProviderConfig.classify('deepseek-chat'), ProviderKind.openai);
  });

  test('预设的 DeepSeek 是 Claude 协议 + /anthropic 端点', () {
    final preset = ProviderConfig.defaultsFor('DeepSeek');
    expect(preset.providerType, ProviderKind.claude);
    expect(preset.baseUrl, 'https://api.deepseek.com/anthropic');
  });

  test('显式选择的类型优先', () {
    for (final kind in [ProviderKind.openai, ProviderKind.claude]) {
      final cfg = ProviderConfig.fromJson({
        'id': 'DeepSeek',
        'name': 'DeepSeek',
        'apiKey': 'k',
        'baseUrl': 'https://api.deepseek.com/anthropic',
        'providerType': kind.name,
      });
      expect(cfg.providerType, kind, reason: kind.name);
    }
  });

  test('旧备份无类型时按地址判定', () {
    Map<String, dynamic> legacy(String baseUrl) => {
      'id': 'DeepSeek',
      'name': 'DeepSeek',
      'apiKey': 'k',
      'baseUrl': baseUrl,
    };

    expect(
      ProviderConfig.fromJson(
        legacy('https://api.deepseek.com/anthropic'),
      ).providerType,
      ProviderKind.claude,
    );
    for (final url in [
      'https://api.deepseek.com/v1',
      'https://api.deepseek.com',
    ]) {
      expect(
        ProviderConfig.fromJson(legacy(url)).providerType,
        ProviderKind.openai,
        reason: url,
      );
    }
  });

  test('协议决定请求形状：Claude 用 anthropicEffort，OpenAI 用 thinkingType', () {
    ProviderConfig cfg(ProviderKind kind) => ProviderConfig.fromJson({
      'id': 'DeepSeek',
      'name': 'DeepSeek',
      'apiKey': 'k',
      'baseUrl': 'https://api.deepseek.com/anthropic',
      'providerType': kind.name,
    });

    expect(
      VendorDefaults.forProvider(cfg(ProviderKind.claude)).dialect,
      ReasoningDialect.anthropicEffort,
    );
    expect(
      VendorDefaults.forProvider(cfg(ProviderKind.openai)).dialect,
      ReasoningDialect.thinkingType,
    );
  });
}
