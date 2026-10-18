import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/model_spec.dart';
import 'package:Kelivo/core/services/model_spec/model_defaults_guesser.dart';

/// GPT-5 系列没有“关闭思考”这一档：最低是 minimal。
/// 上游 2026-10-16 修正了默认值（此前写成 none）。
void main() {
  test('GPT-5 家族的最低档是 minimal', () {
    for (final id in [
      'gpt-5',
      'gpt-5-mini',
      'gpt-5-nano',
      'gpt-5-2025-08-07',
      'openai/gpt-5',
      'openai/gpt-5-mini-2025-08-07',
    ]) {
      final spec = ModelDefaultsGuesser.guess(id).reasoning;
      expect(spec, isNotNull, reason: id);
      expect(spec!.levels, const [
        ReasoningLevel.minimal,
        ReasoningLevel.low,
        ReasoningLevel.medium,
        ReasoningLevel.high,
      ], reason: id);
      expect(spec.canDisable, isFalse, reason: id);
      expect(spec.dialect, ReasoningDialect.openaiReasoningEffort, reason: id);
    }
  });

  test('GPT-5 不再提供“关闭思考”档', () {
    for (final id in ['gpt-5', 'gpt-5-mini']) {
      final spec = ModelDefaultsGuesser.guess(id).reasoning!;
      expect(spec.levels.contains(ReasoningLevel.off), isFalse, reason: id);
      expect(spec.canDisable, isFalse, reason: id);
    }
  });
}
