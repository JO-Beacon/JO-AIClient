import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/settings/pages/theme_settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/ios_switch.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';
import 'package:Kelivo/theme/palettes.dart';
import 'package:Kelivo/theme/theme_factory.dart';

import '../../support/business_test_harness.dart';

/// 手机端主题设置里的“分层表单瓦片”：默认开，点一下关掉并落盘。
void main() {
  testWidgets('theme settings toggles layered sheet tiles', (tester) async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    addTearDown(settings.dispose);
    await settings.loaded;
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ThemeSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.text('Layered sheet tiles');
    await tester.scrollUntilVisible(
      row,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(settings.useLayeredSheetTiles, isTrue);

    await tester.tap(
      find.descendant(
        of: find.ancestor(of: row, matching: find.byType(Row)).first,
        matching: find.byType(IosSwitch),
      ),
    );
    await tester.pumpAndSettle();

    expect(settings.useLayeredSheetTiles, isFalse);
    expect(
      await harness.repository.getPreference(
        'display_use_layered_sheet_tiles_v1',
      ),
      isFalse,
    );
  });

  testWidgets('手机端主题设置的卡片使用分层表面颜色', (tester) async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    addTearDown(settings.dispose);
    await settings.loaded;
    await settings.setUseLayeredSurfaces(true);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final theme = buildLightThemeForScheme(
      ThemePalettes.defaultPalette.light,
      layeredSurfaces: true,
    );
    final semantic = theme.extension<AppSemanticColors>()!;
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          theme: theme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ThemeSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.text('Layered surfaces');
    final containers = tester.widgetList<Container>(
      find.ancestor(of: row, matching: find.byType(Container)),
    );
    final card = containers.firstWhere((container) {
      final decoration = container.decoration;
      return decoration is BoxDecoration && decoration.color != null;
    });

    expect((card.decoration! as BoxDecoration).color, semantic.surfaceCard);
  });
}
