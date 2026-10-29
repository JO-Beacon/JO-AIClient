import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/compress_context_options.dart';
import 'package:Kelivo/core/models/context_compression_task.dart';
import 'package:Kelivo/core/models/context_operation.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/features/chat/widgets/context_node_divider.dart';
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/widgets/message_list_view.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../../support/business_test_harness.dart';

List<ChatMessage> _messages() => [
  ChatMessage(
    id: 'm1',
    role: 'user',
    content: 'first question',
    conversationId: 'c1',
  ),
  ChatMessage(
    id: 'm2',
    role: 'assistant',
    content: 'first answer',
    conversationId: 'c1',
  ),
];

Widget _harness({
  required List<ContextOperation> operations,
  ContextCompressionTask? task,
  VoidCallback? onOpen,
  VoidCallback? onUndo,
}) {
  final messages = _messages();
  final scrollController = ScrollController();
  final listController = ListController();
  addTearDown(scrollController.dispose);
  addTearDown(listController.dispose);
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
        create: (_) => TtsProvider(preferences: createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider(
        create: (_) => UserProvider(preferences: createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider(create: (_) => AskUserInteractionService()),
      ChangeNotifierProvider(create: (_) => ToolApprovalService()),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MessageListView(
          scrollController: scrollController,
          listController: listController,
          messages: messages,
          byGroup: {
            for (final message in messages) message.id: [message],
          },
          reasoning: const {},
          reasoningSegments: const {},
          contentSplits: const {},
          toolParts: const {},
          translations: const {},
          selecting: false,
          selectedItems: const {},
          dividerPadding: EdgeInsets.zero,
          contextOperations: operations,
          contextTask: task,
          contextTaskRevision: task == null
              ? null
              : '${task.id}:${task.phase.name}:${task.anchorGroupId}',
          onOpenContextOperation: onOpen == null
              ? null
              : (operation) => onOpen(),
          onUndoContextOperation: onUndo == null
              ? null
              : (operation) => onUndo(),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('clear operation renders inline at its anchor message', (
    tester,
  ) async {
    var opened = 0;
    var undone = 0;
    final operation = ContextOperation(
      id: 'op-clear',
      kind: ContextOperationKind.clear,
      anchorGroupId: 'm2',
      appliedAfterGroupId: 'm2',
      sourceGroups: const ['m1', 'm2'],
      dependencies: const [],
      createdAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      _harness(
        operations: [operation],
        onOpen: () => opened++,
        onUndo: () => undone++,
      ),
    );
    await tester.pump();

    expect(find.byType(ContextOperationDivider), findsOneWidget);
    expect(find.text('Clear Context'), findsOneWidget);

    await tester.tap(find.text('Clear Context'));
    expect(opened, 1);
    await tester.tap(find.byKey(const ValueKey('undo-context-op-clear')));
    expect(undone, 1);
  });

  testWidgets('running compression task renders at its anchor', (tester) async {
    final task = ContextCompressionTask(
      id: 'task-1',
      conversationId: 'c1',
      options: const CompressContextOptions(
        mode: CompressContextLimitMode.unlimited,
      ),
      phase: CompressionPhase.summarizing,
    )..anchorGroupId = 'm2';

    await tester.pumpWidget(_harness(operations: const [], task: task));
    await tester.pump();

    expect(find.byType(ContextOperationDivider), findsOneWidget);
    expect(find.text('Compressing context'), findsOneWidget);
  });
}
