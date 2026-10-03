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

  testWidgets('生成结束时末条高度必须重新测量（真机日志：账面到底却仍滑不到底）', (tester) async {
    tester.view.physicalSize = const Size(1170, 2100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey<_ProbeHarnessState>();
    await tester.pumpWidget(_ProbeHarness(key: key));
    await tester.pump(const Duration(milliseconds: 50));
    final state = key.currentState!;
    final listController = state.scrollCtrl.messageListController;

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
    final lastIndex = listController.numberOfItems - 1;
    final before = listController.extentForIndex(lastIndex);
    expect(before, isNotNull, reason: '末条应有测量值');

    // 生成结束：只把末条 isStreaming 由真变假，内容不变。
    // 真机上这一刻会挂上操作栏，末条变高；已量过的高度必须失效并重测，
    // 否则账面底部偏小，gap=0 时末条仍滑不进视口。
    state.finishStreamingTail();
    for (var i = 0; i < 5; i++) {
      tester.binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
    }

    final after = listController.extentForIndex(lastIndex);
    expect(after, isNotNull, reason: '重测后末条应有测量值');
    expect(
      after.$1,
      isNot(before.$1),
      reason:
          '生成结束后末条渲染状态变了，已量过的高度必须失效并重测'
          '（旧值 ${before.$1.toStringAsFixed(1)}，重测后 ${after.$1.toStringAsFixed(1)}）',
    );
    final position = state.scrollController.position;
    expect(
      position.maxScrollExtent - position.pixels,
      lessThan(1),
      reason: '重测后仍应停在真实末尾',
    );
  });

  testWidgets('末条在屏外被换成更高的内容后，仍然必须能滑到底并看见它', (tester) async {
    tester.view.physicalSize = const Size(1170, 2100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey<_ProbeHarnessState>();
    await tester.pumpWidget(_ProbeHarness(key: key));
    await tester.pump(const Duration(milliseconds: 50));
    final state = key.currentState!;
    final listController = state.scrollCtrl.messageListController;

    // 预热：让预计算把屏外高度量完
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

    // 滑到最上面：末条离开布局，只剩预计算留下的高度
    state.scrollController.jumpTo(0);
    for (var i = 0; i < 3; i++) {
      tester.binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
    }

    // 末条在屏外时被换成更高的新内容（等价于重新生成后尾巴换人）
    state.replaceTailWithLonger();
    for (var i = 0; i < 5; i++) {
      tester.binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
    }

    // 再滑到底：必须真的到达末尾，且末条出现在可视区
    final position = state.scrollController.position;
    state.scrollController.jumpTo(position.maxScrollExtent);
    for (var i = 0; i < 5; i++) {
      tester.binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
    }

    final visible = state.scrollCtrl.messageListController.visibleRange;
    final lastIndex = listController.numberOfItems - 1;
    expect(
      position.maxScrollExtent - position.pixels,
      lessThan(1),
      reason: '应当停在账面末尾',
    );
    expect(
      visible?.$2,
      lastIndex,
      reason: '滑到底后末条必须在可视区内（末项 ${visible?.$2} / 末条 $lastIndex）',
    );
  });

  testWidgets('末条在屏外被换成更长的分支（条目数量也变）后，仍然必须能滑到底并看见末条', (tester) async {
    tester.view.physicalSize = const Size(1170, 2100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey<_ProbeHarnessState>();
    await tester.pumpWidget(_ProbeHarness(key: key));
    await tester.pump(const Duration(milliseconds: 50));
    final state = key.currentState!;
    final listController = state.scrollCtrl.messageListController;

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
    final countBefore = listController.numberOfItems;

    // 滑到最上面：末条离开布局
    state.scrollController.jumpTo(0);
    for (var i = 0; i < 3; i++) {
      tester.binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
    }

    // 末条屏外时换成更长的分支：条目数量发生变化
    state.replaceTailWithLongerBranch();
    for (var i = 0; i < 5; i++) {
      tester.binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      listController.numberOfItems,
      greaterThan(countBefore),
      reason: '本用例要求走"条目数量变化"那条路',
    );

    // 滑到底：必须真的到达末尾，且末条在可视区内
    final position = state.scrollController.position;
    state.scrollController.jumpTo(position.maxScrollExtent);
    for (var i = 0; i < 5; i++) {
      tester.binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
    }

    final visible = state.scrollCtrl.messageListController.visibleRange;
    final lastIndex = listController.numberOfItems - 1;
    expect(
      position.maxScrollExtent - position.pixels,
      lessThan(1),
      reason: '应当停在账面末尾',
    );
    expect(
      visible?.$2,
      lastIndex,
      reason: '滑到底后末条必须在可视区内（末项 ${visible?.$2} / 末条 $lastIndex）',
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

  /// 模拟"重新生成靠前的消息后，末尾那条换成了新分支的内容"。
  /// 长度保持不变，只把末条换成明显更高的一条。
  void replaceTailWithLonger() {
    setState(() {
      messages = <ChatMessage>[
        ...messages.sublist(0, messages.length - 1),
        ChatMessage(
          id: 'new-branch-tail',
          role: 'assistant',
          content: _longBody(2001) + _longBody(2002) + _longBody(2003),
          conversationId: 'conversation-1',
        ),
      ];
    });
  }

  /// 模拟重新生成靠前消息后，末尾换成**更长的**新分支：条目数量也发生变化。
  void replaceTailWithLongerBranch() {
    setState(() {
      messages = <ChatMessage>[
        ...messages.sublist(0, messages.length - 1),
        ChatMessage(
          id: 'new-branch-a',
          role: 'assistant',
          content: _longBody(2001),
          conversationId: 'conversation-1',
        ),
        ChatMessage(
          id: 'new-branch-b',
          role: 'user',
          content: _longBody(2002),
          conversationId: 'conversation-1',
        ),
        ChatMessage(
          id: 'new-branch-tail',
          role: 'assistant',
          content: _longBody(2003) + _longBody(2004),
          conversationId: 'conversation-1',
        ),
      ];
    });
  }

  void finishStreamingTail() {
    setState(() {
      messages = <ChatMessage>[
        ...messages.sublist(0, messages.length - 1),
        messages.last.copyWith(isStreaming: false),
      ];
    });
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
