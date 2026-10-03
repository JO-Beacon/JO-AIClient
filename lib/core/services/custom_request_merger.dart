import 'model_override_payload_parser.dart';

class CustomRequestMerger {
  static const Set<String> _protectedAssistantHeaders = {'x-conversation-id'};

  static Map<String, String> mergeHeaders({
    Map<String, String> base = const <String, String>{},
    Map<String, String>? assistant,
    Map<String, String> providerAutomatic = const <String, String>{},
    Map<String, String> provider = const <String, String>{},
    Map<String, String> model = const <String, String>{},
  }) {
    final protected = <String, String>{};
    final ordinaryAssistant = <String, String>{};
    if (assistant != null) {
      for (final entry in assistant.entries) {
        if (_protectedAssistantHeaders.contains(entry.key.toLowerCase())) {
          protected[entry.key] = entry.value;
        } else {
          ordinaryAssistant[entry.key] = entry.value;
        }
      }
    }

    final merged = <String, String>{};
    for (final layer in <Map<String, String>>[
      base,
      ordinaryAssistant,
      providerAutomatic,
      provider,
      model,
      protected,
    ]) {
      _addHeadersCaseInsensitive(merged, layer);
    }
    return merged;
  }

  static Map<String, dynamic> mergeBody({
    Map<String, dynamic>? assistant,
    Object? providerRows,
    Map<String, dynamic> model = const <String, dynamic>{},
  }) {
    final merged = <String, dynamic>{};
    if (assistant != null) {
      for (final entry in assistant.entries) {
        final value = entry.value;
        merged[entry.key] = value is String
            ? ModelOverridePayloadParser.parseOverrideValue(value)
            : value;
      }
    }
    // 助手级、供应商级、模型级很可能写在同一层嵌套对象里，必须逐键深合并；
    // 浅覆盖会让后一级把前一级的**同级键**整块顶掉（上游为此单独做过修复）。
    applyBody(
      merged,
      ModelOverridePayloadParser.customBodyFromRows(providerRows),
    );
    applyBody(merged, model);
    return merged;
  }

  /// 需要整块替换的对象：这些字段内部的键互斥（`type: disabled` 与
  /// `budget_tokens`、`thinkingLevel` 与 `thinkingBudget` 等），
  /// 自定义值必须整体生效，不能逐键合并。
  static const Set<String> _replacedWhole = {
    'thinking',
    'reasoning',
    'thinkingConfig',
  };

  /// 把自定义 [body] 合并进已构建好的请求 [target]。自定义值优先；
  /// 嵌套对象逐键合并，使生成出来的同级字段（例如 token 上限）在自定义对象
  /// 只写一部分时仍能保留。数组、标量与 [_replacedWhole] 内的对象整块替换。
  static void applyBody(
    Map<String, dynamic> target,
    Map<String, dynamic> body,
  ) {
    for (final entry in body.entries) {
      final existing = target[entry.key];
      final incoming = entry.value;
      if (existing is Map &&
          incoming is Map &&
          !_replacedWhole.contains(entry.key)) {
        final merged = <String, dynamic>{
          for (final e in existing.entries) e.key.toString(): e.value,
        };
        applyBody(merged, {
          for (final e in incoming.entries) e.key.toString(): e.value,
        });
        target[entry.key] = merged;
      } else {
        target[entry.key] = incoming;
      }
    }
  }

  static void _addHeadersCaseInsensitive(
    Map<String, String> target,
    Map<String, String> layer,
  ) {
    for (final entry in layer.entries) {
      final normalized = entry.key.toLowerCase();
      target.removeWhere((key, _) => key.toLowerCase() == normalized);
      target[entry.key] = entry.value;
    }
  }
}
