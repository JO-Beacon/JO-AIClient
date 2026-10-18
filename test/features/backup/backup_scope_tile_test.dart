import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/models/backup_scope.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/backup/widgets/backup_scope_tile.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/ios_switch.dart';

import '../../support/business_test_harness.dart';

void main() {
  testWidgets('范围选择器能改一类并回传', (tester) async {
    BackupScope? changed;
    final settings = SettingsProvider(createBusinessTestPreferences());
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BackupScopeTile(
              scope: const BackupScope(),
              onChanged: (scope) => changed = scope,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('backup-scope-tile')));
    await tester.pumpAndSettle();

    // 列表可滚动，视口内只构建一部分；第 4 个是供应商。
    expect(find.byType(IosSwitch), findsWidgets);
    await tester.tap(find.byType(IosSwitch).at(3));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(changed, isNotNull);
    expect(changed!.includes(BackupCategory.providers), isFalse);
    expect(changed!.includes(BackupCategory.chats), isTrue);
  });
}
