import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';

import '../../support/business_preferences_test_harness.dart';

class _RecordingChatService extends ChatService {
  _RecordingChatService();

  final List<String> deletedConversationsFor = <String>[];
  final List<({String from, String to})> movedConversations = [];

  @override
  Future<void> deleteConversationsForAssistant(String assistantId) async {
    deletedConversationsFor.add(assistantId);
  }

  @override
  Future<int> moveAllConversationsFromAssistant({
    required String fromAssistantId,
    required String toAssistantId,
  }) async {
    movedConversations.add((from: fromAssistantId, to: toAssistantId));
    return 0;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BusinessPreferencesTestHarness harness;
  late BusinessPreferencesTestSession session;

  setUp(() async {
    harness = await BusinessPreferencesTestHarness.create();
    session = await harness.open();
  });

  tearDown(() => harness.dispose());

  Future<AssistantProvider> load(
    List<Map<String, Object?>> assistants, {
    ChatService? chatService,
  }) async {
    await session.preferences.setString(
      'assistants_v1',
      jsonEncode(assistants),
    );
    final provider = AssistantProvider(
      preferences: session.preferences,
      chatService: chatService,
    );
    await provider.loaded;
    return provider;
  }

  group('AssistantProvider 身份', () {
    test('坏掉的助手数据在写入时就被拒，不会落成空列表', () async {
      await expectLater(
        session.preferences.setString('assistants_v1', '{broken'),
        throwsA(isA<FormatException>()),
      );
    });

    test('未指定助手是列表里的真实条目，缺失归属都落到它', () async {
      final provider = await load(const [
        {'id': 'assistant-a', 'name': 'Assistant A'},
        {'id': 'assistant-b', 'name': 'Assistant B'},
      ]);
      await provider.ensureUnassignedAssistant('Unassigned');

      expect(
        provider.assistants.first.id,
        AssistantProvider.unassignedAssistantId,
      );
      expect(
        provider.assistants.any(
          (a) => a.id == AssistantProvider.unassignedAssistantId,
        ),
        isTrue,
      );
      final resolved = provider.resolveConversationAssistant('missing');
      expect(resolved?.id, AssistantProvider.unassignedAssistantId);

      // 切换选中不影响孤立会话的归属。
      await provider.setCurrentAssistant('assistant-b');
      expect(
        provider.resolveConversationAssistant('missing')?.id,
        AssistantProvider.unassignedAssistantId,
      );
    });

    test('未绑定归属的会话跟随当前选中', () async {
      final provider = await load(const [
        {'id': 'assistant-a', 'name': 'Assistant A'},
        {'id': 'assistant-b', 'name': 'Assistant B'},
      ]);

      expect(provider.resolveConversationAssistant(null)?.id, 'assistant-a');
      await provider.setCurrentAssistant('assistant-b');
      expect(provider.resolveConversationAssistant(null)?.id, 'assistant-b');
    });

    test('删除助手默认把会话转给未指定助手，勾选后才直接删除', () async {
      final chat = _RecordingChatService();
      final provider = await load(const [
        {'id': 'assistant-a', 'name': 'Assistant A'},
        {'id': 'assistant-b', 'name': 'Assistant B'},
        {'id': 'assistant-c', 'name': 'Assistant C'},
      ], chatService: chat);
      await provider.ensureUnassignedAssistant('Unassigned');

      expect(await provider.deleteAssistant('assistant-a'), isTrue);
      expect(chat.movedConversations, [
        (from: 'assistant-a', to: AssistantProvider.unassignedAssistantId),
      ]);
      expect(chat.deletedConversationsFor, isEmpty);
      expect(
        provider.resolveConversationAssistant('assistant-a')?.id,
        AssistantProvider.unassignedAssistantId,
      );

      expect(
        await provider.deleteAssistant(
          'assistant-b',
          deleteConversations: true,
        ),
        isTrue,
      );
      expect(chat.deletedConversationsFor, ['assistant-b']);
    });

    test('未指定助手本身不能被删除', () async {
      final provider = await load(const [
        {'id': 'assistant-a', 'name': 'Assistant A'},
        {'id': 'assistant-b', 'name': 'Assistant B'},
      ]);
      await provider.ensureUnassignedAssistant('Unassigned');

      expect(
        await provider.deleteAssistant(AssistantProvider.unassignedAssistantId),
        isFalse,
      );
      expect(
        provider.assistants.any(
          (a) => a.id == AssistantProvider.unassignedAssistantId,
        ),
        isTrue,
      );
    });
  });
}
