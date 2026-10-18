import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/section_card.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';
import 'package:Kelivo/theme/theme_factory.dart';

import '../../support/business_test_harness.dart';

/// 面板瓦片：开关开着时铺“卡片上的输入框”那一档底色，关掉时透明；
/// 分隔线跟着开关走。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsProvider> pumpTile(WidgetTester tester) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    addTearDown(settings.dispose);
    await settings.loaded;
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          theme: buildLightThemeForScheme(
            ColorScheme.fromSeed(
              seedColor: const Color(0xFF4D5C92),
              brightness: Brightness.light,
            ),
            layeredSurfaces: true,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ColoredBox(
                    key: const ValueKey('tile'),
                    color: sheetTileColor(context),
                    child: const SizedBox(width: 8, height: 8),
                  ),
                  // 分隔线开关也要在 build 里读，否则 watch 会落到 fallback。
                  Builder(
                    builder: (context) => Text(
                      showSheetTileDividers(context)
                          ? 'dividers-on'
                          : 'dividers-off',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  testWidgets('默认开着，用卡片上的输入框那一档底色', (tester) async {
    await pumpTile(tester);

    final colors = Theme.of(
      tester.element(find.byKey(const ValueKey('tile'))),
    ).extension<AppSemanticColors>()!;
    final tile = tester.widget<ColoredBox>(find.byKey(const ValueKey('tile')));
    expect(tile.color, colors.surfaceCardFill);
    expect(tile.color, isNot(Colors.transparent));
    expect(find.text('dividers-on'), findsOneWidget);
  });

  testWidgets('关掉后瓦片透明，分隔线也不画', (tester) async {
    final settings = await pumpTile(tester);

    await settings.setUseLayeredSheetTiles(false);
    await tester.pumpAndSettle();

    final tile = tester.widget<ColoredBox>(find.byKey(const ValueKey('tile')));
    expect(tile.color, Colors.transparent);
    expect(find.text('dividers-off'), findsOneWidget);
  });
}
