import "../../../support/business_test_harness.dart";
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/features/home/controllers/stream_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const {});

  StreamController buildController(SettingsProvider settings) =>
      StreamController(
        chatService: ChatService(),
        onStateChanged: () {},
        getSettingsProvider: () => settings,
        getCurrentConversationId: () => 'conversation-1',
      );

  StreamingState buildStreamingState(SettingsProvider settings) {
    final message = ChatMessage(
      id: 'assistant-message',
      role: 'assistant',
      content: '',
      conversationId: 'conversation-1',
      isStreaming: true,
    );
    return StreamingState(
      GenerationContext(
        assistantMessage: message,
        apiMessages: const [],
        userImagePaths: const [],
        allowImagesApiRouting: false,
        providerKey: 'test',
        modelId: 'test-model',
        assistant: null,
        settings: settings,
        config: ProviderConfig(
          id: 'test',
          enabled: true,
          name: 'Test',
          apiKey: '',
          baseUrl: '',
        ),
        toolDefs: const [],
        supportsReasoning: true,
        enableReasoning: true,
        streamOutput: true,
      ),
    );
  }

  Future<void> noopPersist(
    String messageId, {
    String? reasoningText,
    DateTime? reasoningFinishedAt,
    String? reasoningSegmentsJson,
  }) async {}

  testWidgets('同一段推理 id 在正文打断后继续时复用片段并恢复计时，而不是停住', (tester) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    final controller = buildController(settings);
    addTearDown(controller.dispose);
    final state = buildStreamingState(settings);

    await controller.handleReasoningChunk('第一段思考', state, reasoningId: 'r0');
    final first = controller.getReasoningSegments(state.messageId)!;
    expect(first, hasLength(1));
    expect(first.single.startAt, isNotNull);
    expect(first.single.finishedAt, isNull);

    // 正文开始：当前思考片段被标记为结束。
    await controller.finishReasoningOnContent(
      state,
      updateReasoningInDb: noopPersist,
    );
    expect(
      controller.getReasoningSegments(state.messageId)!.single.finishedAt,
      isNotNull,
    );

    // 同一 id 的推理再次到来：沿用同一片段并把结束时间清掉，
    // 界面上的耗时计时才会继续走。
    await controller.handleReasoningChunk('续写思考', state, reasoningId: 'r0');
    final segments = controller.getReasoningSegments(state.messageId)!;
    expect(segments, hasLength(1));
    expect(segments.single.text, '第一段思考续写思考');
    expect(segments.single.finishedAt, isNull);
    expect(segments.single.startAt, isNotNull);
    await tester.pump(const Duration(milliseconds: 60));
  });

  testWidgets('推理 id 变化时开新片段并带上自己的开始时间', (tester) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    final controller = buildController(settings);
    addTearDown(controller.dispose);
    final state = buildStreamingState(settings);

    await controller.handleReasoningChunk('第一段思考', state, reasoningId: 'r0');
    await controller.finishReasoningOnContent(
      state,
      updateReasoningInDb: noopPersist,
    );
    await controller.handleReasoningChunk('第二段思考', state, reasoningId: 'r1');

    final segments = controller.getReasoningSegments(state.messageId)!;
    expect(segments, hasLength(2));
    expect(segments.first.finishedAt, isNotNull);
    expect(segments.last.text, '第二段思考');
    expect(segments.last.startAt, isNotNull);
    expect(segments.last.finishedAt, isNull);
    await tester.pump(const Duration(milliseconds: 60));
  });

  testWidgets('同一段推理 id 跨工具边界时开新段，工具耗时不算进思考时长', (tester) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    final controller = buildController(settings);
    addTearDown(controller.dispose);
    final state = buildStreamingState(settings);

    await controller.handleReasoningChunk('先想一下', state, reasoningId: 'r0');
    // 工具开始：片段被标记为结束，并与渲染部件一样在工具边界切断。
    await controller.handleToolCallsChunk(
      ToolCallStart(id: 'call-1', toolName: 'lookup'),
      state,
      updateReasoningSegmentsInDb: (_, _) async {},
      setToolEventsInDb: (_, _) async {},
      getToolEventsFromDb: (_) => const [],
    );
    await controller.handleReasoningChunk('工具后再想', state, reasoningId: 'r0');
    final segments = controller.getReasoningSegments(state.messageId)!;
    // 工具前、工具后各一段，各自计时；工具执行时间不落在任何一段里。
    expect(segments, hasLength(2));
    expect(segments.first.text, '先想一下');
    expect(segments.first.finishedAt, isNotNull);
    expect(segments.last.text, '工具后再想');
    expect(segments.last.startAt, isNotNull);
    expect(segments.last.finishedAt, isNull);
    await tester.pump(const Duration(milliseconds: 60));
  });

  testWidgets('没有推理 id 时保留按工具边界切分的旧规则', (tester) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    final controller = buildController(settings);
    addTearDown(controller.dispose);
    final state = buildStreamingState(settings);

    await controller.handleReasoningChunk('先想一下', state);
    await controller.handleToolCallsChunk(
      ToolCallStart(id: 'call-1', toolName: 'lookup'),
      state,
      updateReasoningSegmentsInDb: (_, _) async {},
      setToolEventsInDb: (_, _) async {},
      getToolEventsFromDb: (_) => const [],
    );
    await controller.handleReasoningChunk('工具后再想', state);

    final segments = controller.getReasoningSegments(state.messageId)!;
    expect(segments, hasLength(2));
    expect(segments.last.finishedAt, isNull);
    await tester.pump(const Duration(milliseconds: 60));
  });
}
