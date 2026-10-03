import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 本仓库**不得**使用「兜底 API 密钥」。
///
/// 上游（Kelivo）在 `lib/secrets/fallback.dart` 里放了一个内置密钥
/// （`const String siliconflowFallbackKey = ...`），并在 `chat_api_helpers.dart` 的
/// `effectiveApiKey` 里兜底：用户没填 key、且是 SiliconFlow、且模型在允许名单内时，
/// 直接用那个内置 key 发请求。
///
/// 这与 `AGENTS.md` 第 3.6 节冲突：**不得在仓库或构建工作流中注入、保存或使用供应商
/// API 密钥；供应商只能使用用户在应用配置中明确填写的密钥。** JO 当初没有采纳这段
/// （已知的有意差异），这里用门禁把它钉死，防止以后基线合并照上游补回来。
void main() {
  test('仓库内不存在兜底 API 密钥的实现文件', () {
    expect(
      File('lib/secrets/fallback.dart').existsSync(),
      isFalse,
      reason: '不得把内置供应商密钥带进仓库（AGENTS 3.6）',
    );
  });

  test('lib/ 下不得引用兜底密钥或 secrets/fallback', () async {
    const forbidden = <String>[
      'siliconflowFallbackKey',
      'secrets/fallback.dart',
    ];
    final offenders = <String>[];
    await for (final entity in Directory('lib').list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = await entity.readAsString();
      for (final token in forbidden) {
        if (source.contains(token)) {
          offenders.add('${entity.path}: $token');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '供应商只能使用用户明确填写的密钥；基线合并把上游的兜底密钥带回来时必须在合并后删除',
    );
  });
}
