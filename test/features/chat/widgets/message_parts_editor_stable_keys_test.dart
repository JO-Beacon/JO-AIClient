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

  testWidgets('续答分界可见，但没有删除按钮', (tester) async {
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
                parts: const [
                  TextPart('A'),
                  AssistantRoundEndPart(),
                  TextPart('B'),
                ],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

    // 分界仍占一行，能看见；但两个正文部件只对应两个删除按钮。
    expect(
      find.textContaining(l10n.messageEditAssistantRoundEndPart),
      findsOneWidget,
    );
    expect(find.byIcon(Lucide.Trash2), findsNWidgets(2));
  });
}
