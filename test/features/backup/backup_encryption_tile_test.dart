import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/backup/widgets/backup_encryption_tile.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

void main() {
  testWidgets('password visibility button does not cover the input field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BackupEncryptionTile(
            password: null,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('backup-encryption-switch')));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('backup-password'));
    final visibility = find.byKey(const ValueKey('backup-password-visibility'));
    final fieldRect = tester.getRect(field);
    final visibilityRect = tester.getRect(visibility);

    expect(visibilityRect.width, lessThanOrEqualTo(40));
    expect(visibilityRect.right, lessThanOrEqualTo(fieldRect.right));

    await tester.tapAt(
      Offset(fieldRect.left + 24, fieldRect.center.dy),
    );
    await tester.pump();
    await tester.enterText(field, 'secret');
    await tester.pump();

    final editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)).first,
    );
    expect(editable.controller.text, 'secret');
    expect(editable.focusNode.hasFocus, isTrue);
  });
}
