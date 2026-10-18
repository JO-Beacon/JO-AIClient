import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';

import '../../support/business_preferences_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BusinessPreferencesTestHarness harness;
  late BusinessPreferencesTestSession session;

  setUp(() async {
    harness = await BusinessPreferencesTestHarness.create();
    session = await harness.open();
  });

  tearDown(() => harness.dispose());

  Future<AssistantProvider> load(List<Map<String, Object?>> assistants) async {
    await session.preferences.setString(
      'assistants_v1',
      jsonEncode(assistants),
    );
    final provider = AssistantProvider(preferences: session.preferences);
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

    test('归属助手缺失时落到持久化的恢复助手，并保持稳定', () async {
      final provider = await load(const [
        {'id': 'assistant-a', 'name': 'Assistant A'},
        {'id': 'assistant-b', 'name': 'Assistant B'},
      ]);

      // 会话指向一个已不存在的助手。
      final resolved = provider.resolveConversationAssistant('missing');
      expect(resolved?.id, 'assistant-a');
      expect(
        session.preferences.getString('orphaned_conversations_assistant_id_v1'),
        'assistant-a',
      );

      // 切换选中不影响孤立会话的归属。
      await provider.setCurrentAssistant('assistant-b');
      expect(
        provider.resolveConversationAssistant('missing')?.id,
        'assistant-a',
      );
    });

    test('恢复助手被删除后才改挂到另一个存在的助手', () async {
      final provider = await load(const [
        {'id': 'assistant-a', 'name': 'Assistant A'},
        {'id': 'assistant-b', 'name': 'Assistant B'},
      ]);
      expect(
        provider.resolveConversationAssistant('missing')?.id,
        'assistant-a',
      );

      expect(await provider.deleteAssistant('assistant-a'), isTrue);

      expect(
        provider.resolveConversationAssistant('missing')?.id,
        'assistant-b',
      );
      expect(
        session.preferences.getString('orphaned_conversations_assistant_id_v1'),
        'assistant-b',
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
  });
}
