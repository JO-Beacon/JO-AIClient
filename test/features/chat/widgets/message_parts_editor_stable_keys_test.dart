import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/chat/widgets/message_parts_editor.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../../support/business_test_harness.dart';

/// 删除上面的部件后，下面正在编辑的输入框不能把内容“留”在自己身上：
/// 输入框缓存必须跟着部件走，而不是跟着位置走。
void main() {
  testWidgets('删除靠前的部件后，其余输入框仍显示各自的内容', (tester) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MessagePartsEditor(
                parts: const [TextPart('A'), TextPart('B'), TextPart('C')],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));

    // 让中间的框进入“正在编辑”状态（选区有效）。
    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();

    // 删除第一个部件。
    await tester.tap(find.byIcon(Lucide.Trash2).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(
        AppLocalizations.of(
          tester.element(find.byType(Scaffold)),
        )!.messageEditDeletePart,
      ),
    );
    await tester.pumpAndSettle();

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields, hasLength(2));
    expect(fields.map((field) => field.controller!.text), ['B', 'C']);
  });

  testWidgets('续答分界不在编辑列表里显示，但仍保留在结构里', (tester) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    addTearDown(settings.dispose);
    List<MessagePart>? emitted;
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MessagePartsEditor(
                parts: const [
                  TextPart('A'),
                  AssistantRoundEndPart(),
                  TextPart('B'),
                ],
                onChanged: (parts) => emitted = parts,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

    // 分界没有卡片：两个正文部件，两个删除按钮，编号不跳号。
    expect(
      find.textContaining(l10n.messageEditAssistantRoundEndPart),
      findsNothing,
    );
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byIcon(Lucide.Trash2), findsNWidgets(2));
    expect(
      find.textContaining('1 ${l10n.messageEditTextPart}'),
      findsOneWidget,
    );
    expect(
      find.textContaining('2 ${l10n.messageEditTextPart}'),
      findsOneWidget,
    );

    // 编辑一个字的回传里，分界必须还在原来的位置。
    await tester.enterText(find.byType(TextField).first, 'AA');
    await tester.pump();
    expect(emitted, isNotNull);
    expect(emitted![1], isA<AssistantRoundEndPart>());
  });

  testWidgets('敲字回传新列表时不重建输入框，也不会丢焦点', (tester) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: _LiveEditorHost()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.pump();
    final before = tester.element(field);

    // 与编辑面板一样：每次输入都把新列表回传并重建父级。
    await tester.enterText(field, 'AB');
    await tester.pump();

    expect(tester.element(find.byType(TextField)), same(before));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'AB',
    );
    expect(
      find.byWidgetPredicate((w) => w is EditableText && w.focusNode.hasFocus),
      findsOneWidget,
    );
  });
  testWidgets('删掉空段的最后一个部件后，分界立即从回传列表里消失（不保存）', (tester) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    addTearDown(settings.dispose);
    List<MessagePart>? emitted;
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MessagePartsEditor(
                parts: const [
                  TextPart('A'),
                  AssistantRoundEndPart(),
                  TextPart('B'),
                  AssistantRoundEndPart(),
                ],
                onChanged: (parts) => emitted = parts,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    expect(find.byType(TextField), findsNWidgets(2));

    // 删掉 B（最后一个正文部件），它所在的那个段就变空了。
    await tester.tap(find.byIcon(Lucide.Trash2).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.messageEditDeletePart));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    // 只回传一个分界：变空的第二个已经被收掉。
    expect(emitted, isNotNull);
    expect(emitted!.whereType<AssistantRoundEndPart>(), hasLength(1));
  });

  testWidgets('把正文清空不会触发分界自动删除', (tester) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    addTearDown(settings.dispose);
    List<MessagePart>? emitted;
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MessagePartsEditor(
                parts: const [
                  TextPart('A'),
                  AssistantRoundEndPart(),
                  TextPart('B'),
                ],
                onChanged: (parts) => emitted = parts,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '');
    await tester.pump();

    expect(emitted, isNotNull);
    expect(emitted!.whereType<AssistantRoundEndPart>(), hasLength(1));
    expect(emitted![2], isA<TextPart>());
    expect((emitted![2] as TextPart).text, isEmpty);
  });
  testWidgets('删掉靠前的部件后，展开窗口仍打开对应那个部件的内容', (tester) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: MessagePartsEditor(
                parts: [TextPart('A'), TextPart('B'), TextPart('C')],
                onChanged: _ignoreParts,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

    await tester.tap(find.byIcon(Lucide.Trash2).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.messageEditDeletePart));
    await tester.pumpAndSettle();

    // 现在剩 B、C：展开 C（第二个），弹窗里应当是 C，而不是 B。
    await tester.tap(find.byIcon(Lucide.Maximize2).last);
    await tester.pumpAndSettle();

    final texts = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((field) => field.controller!.text)
        .toList();
    expect(texts.where((text) => text == 'C'), hasLength(2));
  });
}

void _ignoreParts(List<MessagePart> _) {}

class _LiveEditorHost extends StatefulWidget {
  const _LiveEditorHost();

  @override
  State<_LiveEditorHost> createState() => _LiveEditorHostState();
}

class _LiveEditorHostState extends State<_LiveEditorHost> {
  List<MessagePart> _parts = const [TextPart('A')];

  @override
  Widget build(BuildContext context) {
    return MessagePartsEditor(
      parts: _parts,
      onChanged: (parts) => setState(() => _parts = parts),
    );
  }
}
