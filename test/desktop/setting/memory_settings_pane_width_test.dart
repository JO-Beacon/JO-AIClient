import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/desktop/setting/memory_settings_pane.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../support/business_test_harness.dart';

/// 桌面记忆设置面板：宽窗口下内容限制在 960 宽并居中（上游 2026-10-16 修复）。
void main() {
  testWidgets('宽窗口下内容限宽 960 并居中', (tester) async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    addTearDown(settings.dispose);
    await settings.loaded;

    tester.view.physicalSize = const Size(2400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: DesktopMemorySettingsPane()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final content = find.byKey(
      const ValueKey('desktop-memory-settings-constrained'),
    );
    expect(tester.getSize(content).width, 960);

    final rect = tester.getRect(content);
    final leftGap = rect.left;
    final rightGap = 2400 - rect.right;
    expect((leftGap - rightGap).abs(), lessThanOrEqualTo(1));
  });
}
