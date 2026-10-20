import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/features/chat/utils/round_structure.dart';

/// 保存前规整“续答分界”：只有部件全被删掉的段，分界才会被收掉；
/// 正文被清空但部件还在，不算空段。
void main() {
  test('两段分界之间被删空时，后面那个分界被丢掉', () {
    final parts = <MessagePart>[
      const TextPart('A'),
      const ToolCallPart('{"id":"t1","name":"x"}'),
      const AssistantRoundEndPart(),
      // 这一段被用户删光。
      const AssistantRoundEndPart(),
      const TextPart('B'),
    ];
    final normalized = normalizeRoundBoundaries(parts);
    expect(normalized.whereType<AssistantRoundEndPart>(), hasLength(1));
    expect(normalized[2], isA<AssistantRoundEndPart>());
    expect(normalized.last, isA<TextPart>());
  });

  test('正文被清空但部件还在时，分界保留', () {
    final parts = <MessagePart>[
      const TextPart('A'),
      const ToolCallPart('{"id":"t1","name":"x"}'),
      const AssistantRoundEndPart(),
      const TextPart(''),
      const AssistantRoundEndPart(),
      const TextPart('B'),
    ];
    expect(
      normalizeRoundBoundaries(parts).whereType<AssistantRoundEndPart>(),
      hasLength(2),
    );
  });

  test('空推理部件同样算“部件还在”，分界保留', () {
    final parts = <MessagePart>[
      const TextPart('A'),
      const AssistantRoundEndPart(),
      const ReasoningPart(''),
      const AssistantRoundEndPart(),
    ];
    expect(
      normalizeRoundBoundaries(parts).whereType<AssistantRoundEndPart>(),
      hasLength(2),
    );
  });

  test('有内容的分界全部保留', () {
    final parts = <MessagePart>[
      const TextPart('A'),
      const ToolCallPart('{"id":"t1","name":"x"}'),
      const AssistantRoundEndPart(),
      const TextPart('B'),
      const ToolCallPart('{"id":"t2","name":"y"}'),
      const AssistantRoundEndPart(),
    ];
    final normalized = normalizeRoundBoundaries(parts);
    expect(normalized, hasLength(parts.length));
    expect(normalized.whereType<AssistantRoundEndPart>(), hasLength(2));
  });

  test('开头就没有内容的分界被丢掉，末尾分界保留', () {
    final parts = <MessagePart>[
      const AssistantRoundEndPart(),
      const TextPart('A'),
      const AssistantRoundEndPart(),
    ];
    final normalized = normalizeRoundBoundaries(parts);
    expect(normalized.first, isA<TextPart>());
    expect(normalized.last, isA<AssistantRoundEndPart>());
    expect(normalized.whereType<AssistantRoundEndPart>(), hasLength(1));
  });

  test('没有分界的消息内容不变', () {
    final parts = <MessagePart>[const TextPart('A'), const TextPart('B')];
    expect(normalizeRoundBoundaries(parts), parts);
  });
}
