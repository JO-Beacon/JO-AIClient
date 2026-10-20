import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/ios_tactile.dart';
import 'package:Kelivo/shared/widgets/update_release_notes_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/business_test_harness.dart';

void main() {
  testWidgets('tapping the release notes card invokes its callback', (
    tester,
  ) async {
    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider(
          create: (_) => SettingsProvider(createBusinessTestPreferences()),
          child: Scaffold(
            body: UpdateReleaseNotesCard(
              title: 'Update: 1.0.1',
              notes: 'Release notes',
              onTap: () => tapCount++,
              haptics: false,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(IosCardPress));
    await tester.pump();

    expect(tapCount, 1);
  });
}
