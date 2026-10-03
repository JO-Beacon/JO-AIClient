import "../../../support/business_test_harness.dart";
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/features/home/controllers/stream_controller.dart'
    as stream_ctrl;
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/widgets/message_list_view.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

/// 重新生成的确认弹窗有一句本仓库独有的提示：**正在生成时**要额外告诉用户
/// “重新生成会中断正在生成的回复”。
///
/// 这条提示由 `ChatMessageWidget.conversationStreaming` 控制。该值必须由
/// `MessageListView.isConversationGenerating` 一路传下去；一旦断链，它取值处
/// 的默认 `false` 会让提示**静默消失**——弹窗还在、文案也正常，只是那句提醒没了。
/// 所以这里按“会生成 / 不会生成”两种情况各钉一条。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('会话正在生成时，重新生成的确认弹窗会提示会中断生成', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _pumpMessageList(
        tester,
        isConversationGenerating: true,
        onRegenerate: () {},
      );

      await tester.tap(find.byIcon(Lucide.RefreshCw));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Regenerate'), findsOneWidget);
      expect(find.textContaining('interrupt the reply'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('会话没有在生成时，确认弹窗不出现中断提示', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _pumpMessageList(
        tester,
        isConversationGenerating: false,
        onRegenerate: () {},
      );

      await tester.tap(find.byIcon(Lucide.RefreshCw));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Regenerate'), findsOneWidget);
      expect(find.textContaining('interrupt the reply'), findsNothing);
      // 基础文案仍要在：说明弹窗本身没有被这条提示挤掉。
      expect(find.textContaining('creates a new branch'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('确认后回调被触发，取消则不触发', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      var regenerated = 0;
      await _pumpMessageList(
        tester,
        isConversationGenerating: true,
        onRegenerate: () => regenerated++,
      );

      await tester.tap(find.byIcon(Lucide.RefreshCw));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(regenerated, 0);

      await tester.tap(find.byIcon(Lucide.RefreshCw));
      await tester.pumpAndSettle();
      // 弹窗里的确认按钮与标题同名，取按钮那一个。
      await tester.tap(find.widgetWithText(TextButton, 'Regenerate'));
      await tester.pumpAndSettle();
      expect(regenerated, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<void> _pumpMessageList(
  WidgetTester tester, {
  required bool isConversationGenerating,
  required VoidCallback onRegenerate,
}) async {
  await tester.pumpWidget(
    _MessageListHarness(
      isConversationGenerating: isConversationGenerating,
      onRegenerate: onRegenerate,
    ),
  );
  await tester.pumpAndSettle();
}

class _MessageListHarness extends StatefulWidget {
  const _MessageListHarness({
    required this.isConversationGenerating,
    required this.onRegenerate,
  });

  final bool isConversationGenerating;
  final VoidCallback onRegenerate;

  @override
  State<_MessageListHarness> createState() => _MessageListHarnessState();
}

class _MessageListHarnessState extends State<_MessageListHarness> {
  late final ScrollController scrollController;
  late final ListController listController;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController();
    listController = ListController();
  }

  @override
  void dispose() {
    scrollController.dispose();
    listController.dispose();
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
              UserProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              TtsProvider(preferences: createBusinessTestPreferences()),
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
            listController: listController,
            messages: <ChatMessage>[
              ChatMessage(
                id: 'assistant-1',
                role: 'assistant',
                content: 'answer',
                conversationId: 'conversation-1',
              ),
            ],
            byGroup: const {},
            reasoning: const <String, stream_ctrl.ReasoningData>{},
            reasoningSegments:
                const <String, List<stream_ctrl.ReasoningSegmentData>>{},
            contentSplits: const <String, stream_ctrl.ContentSplitData>{},
            toolParts: const {},
            translations: const {},
            selecting: false,
            selectedItems: const {},
            dividerPadding: EdgeInsets.zero,
            isConversationGenerating: widget.isConversationGenerating,
            onRegenerateMessage: (_) => widget.onRegenerate(),
          ),
        ),
      ),
    );
  }
}
