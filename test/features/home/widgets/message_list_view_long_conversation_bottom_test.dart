import "../../../support/business_test_harness.dart";

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/features/home/controllers/scroll_controller.dart'
    as scroll_ctrl;
import 'package:Kelivo/features/home/controllers/streaming_content_notifier.dart';
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/widgets/message_list_view.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tailId = 'probe-tail';

String _longBody(int index) {
  final buffer = StringBuffer('第 $index 条历史消息。\n');
  for (var line = 0; line < 6; line++) {
    buffer.writeln('第 $line 行：这是一段用来撑高度的中文内容，加上一些 emoji 😀 和数字 12345。');
  }
  return buffer.toString();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('多历史消息时预计算能否把屏外高度量完并滚到真实末尾', (tester) async {
    tester.view.physicalSize = const Size(1170, 2100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey<_ProbeHarnessState>();
    await tester.pumpWidget(_ProbeHarness(key: key));
    await tester.pump(const Duration(milliseconds: 50));
    final state = key.currentState!;
    final listController = state.scrollCtrl.messageListController;

    // 模拟“打开一个历史很长的会话，并锚定到底部”；
    // 同时让尾部消息持续流式增长，复现“生成过程中”。
    state.startStreamingTail();
    state.scrollCtrl.positionAtBottomOnNextLayout();
    var frames = 0;
    while (frames < 400) {
      state.pushStreamTick(frames);
      tester.binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
      if (listController.numberOfItemsWithEstimatedExtent == 0) break;
    }
    final position = state.scrollController.position;
    expect(
      listController.numberOfItemsWithEstimatedExtent,
      0,
      reason: '长会话贴底后，屏外高度必须被预计算量完',
    );
    expect(
      position.maxScrollExtent - position.pixels,
      lessThan(1),
      reason: '量完之后列表应停在真实末尾',
    );
  });
}

class _ProbeHarness extends StatefulWidget {
  const _ProbeHarness({super.key});

  @override
  State<_ProbeHarness> createState() => _ProbeHarnessState();
}

class _ProbeHarnessState extends State<_ProbeHarness> {
  final scrollController = scroll_ctrl.ChatAutoFollowScrollController();
  final streamingNotifier = StreamingContentNotifier();
  late final scroll_ctrl.ChatScrollController scrollCtrl;
  final processingFilesMessageId = ValueNotifier<String?>(null);

  void startStreamingTail() {
    streamingNotifier.getNotifier(_tailId);
  }

  void pushStreamTick(int frame) {
    streamingNotifier.updateContent(
      _tailId,
      '流式内容 $frame\n${_longBody(frame)}',
      10,
    );
  }

  late List<ChatMessage> messages = <ChatMessage>[
    for (var index = 0; index < 200; index++)
      ChatMessage(
        id: 'history-$index',
        role: index.isEven ? 'user' : 'assistant',
        content: _longBody(index),
        conversationId: 'conversation-1',
      ),
    ChatMessage(
      id: _tailId,
      role: 'assistant',
      content: _longBody(999),
      conversationId: 'conversation-1',
      isStreaming: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    scrollCtrl = scroll_ctrl.ChatScrollController(
      scrollController: scrollController,
      onStateChanged: () {},
      getAutoScrollEnabled: () => true,
      getAutoScrollIdleSeconds: () => 3,
      isGenerating: () => false,
    );
  }

  @override
  void dispose() {
    scrollCtrl.dispose();
    scrollController.dispose();
    streamingNotifier.dispose();
    processingFilesMessageId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              AssistantProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              TtsProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              UserProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(create: (_) => AskUserInteractionService()),
        ChangeNotifierProvider(create: (_) => ToolApprovalService()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MessageListView(
            scrollController: scrollController,
            listController: scrollCtrl.messageListController,
            messages: messages,
            byGroup: const {},
            versionSelections: const {},
            reasoning: const {},
            reasoningSegments: const {},
            contentSplits: const {},
            toolParts: const {},
            translations: const {},
            selecting: false,
            selectedItems: const {},
            dividerPadding: EdgeInsets.zero,
            processingFilesMessageId: processingFilesMessageId,
            streamingContentNotifier: streamingNotifier,
            onUserScrollIntent: scrollCtrl.handleUserScrollIntent,
          ),
        ),
      ),
    );
  }
}
