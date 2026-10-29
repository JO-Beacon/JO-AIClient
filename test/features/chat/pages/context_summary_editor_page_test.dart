import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/chat/pages/context_summary_editor_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

void main() {
  testWidgets('summary editor saves the edited text and reports budget', (
    tester,
  ) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ContextSummaryEditorPage(
          summary: 'first draft',
          budget: (usedTokens: 1200, contextWindow: 4000),
          onSave: (summary) async {
            saved = summary;
            return true;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Edit summary'), findsNWidgets(2));
    expect(
      find.text(
        'Approx. 1.2k tokens after saving. Editing does not change active context.',
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'edited summary');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, 'edited summary');
  });
}
