import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/backup/widgets/backup_encryption_tile.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/dialogs/loading_task_dialog.dart';

void main() {
  testWidgets('restore password sheet stays above the loading barrier', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late BuildContext pageContext;
    String? entered;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            pageContext = context;
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    entered = await runWithLoadingTaskDialog<String?>(
                      context: context,
                      label: 'Restoring',
                      task: (_) async {
                        await Future<void>.delayed(
                          const Duration(milliseconds: 20),
                        );
                        return showBackupPasswordDialog(
                          pageContext,
                          creating: true,
                        );
                      },
                    );
                  },
                  child: const Text('Start'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final field = find.byKey(const ValueKey('backup-password'));
    expect(field, findsOneWidget);
    final rect = tester.getRect(field);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(844));

    final editableFinder = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    final editable = tester.widget<EditableText>(editableFinder);
    editable.focusNode.unfocus();
    await tester.pump();

    // The loading barrier used to sit above this route, so this tap would
    // never reach the text field. Keep the field itself as the target.
    await tester.tapAt(Offset(rect.left + 24, rect.center.dy));
    await tester.pump();
    expect(editable.focusNode.hasFocus, isTrue);

    await tester.enterText(field, 'secret');
    await tester.pump();
    expect(editable.controller.text, 'secret');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(entered, isNull);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
  });
}
