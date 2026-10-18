import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/message_part.dart';

ChatMessage _message({String id = 'message-1'}) {
  return ChatMessage(
    id: id,
    role: 'assistant',
    parts: const [TextPart('正文')],
    timestamp: DateTime.utc(2026, 10, 18),
    conversationId: 'conversation-1',
  );
}

void main() {
  group('ChatMessage 缓存快照', () {
    test('未水合时提供方数据为空，且不会伪造空快照', () {
      final message = _message();

      expect(message.providerArtifactSnapshot, isEmpty);
      expect(message.hasProviderArtifactSnapshot, isFalse);
    });

    test('水合后不可变，且随同一条消息的副本保留', () {
      final message = _message()
        ..hydrateProviderArtifacts({'claude_turn': '{"a":1}'});

      expect(message.hasProviderArtifactSnapshot, isTrue);
      expect(message.providerArtifactSnapshot['claude_turn'], '{"a":1}');
      expect(
        () => message.providerArtifactSnapshot['other'] = 'x',
        throwsUnsupportedError,
      );

      final copy = message.copyWith(content: '改过的正文');
      expect(copy.providerArtifactSnapshot['claude_turn'], '{"a":1}');
    });

    test('换成另一条消息时清掉快照与顺序标记，避免串到别的消息', () {
      final message = _message()
        ..hydrateProviderArtifacts({'claude_turn': '{"a":1}'})
        ..hydrateStorageOrder(7);

      expect(
        message.copyWith(id: 'message-2').providerArtifactSnapshot,
        isEmpty,
      );
      expect(message.copyWith(id: 'message-2').storageOrder, isNull);
      expect(message.copyWith().storageOrder, 7);
    });

    test('显式空快照与未水合是两种不同状态', () {
      final message = _message()..hydrateProviderArtifacts(const {});

      expect(message.hasProviderArtifactSnapshot, isTrue);
      expect(message.providerArtifactSnapshot, isEmpty);
    });
  });
}
