import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/chat/widgets/tools_sheet_row.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/shared/widgets/ios_tactile.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';
import 'package:Kelivo/theme/theme_factory.dart';

import '../../../support/business_test_harness.dart';

/// 真实面板行（聊天页 ＋ 面板用的瓦片）跟着“分层表单瓦片”开关走：
/// 开着铺卡片底色，关掉透明。
void main() {
  testWidgets('面板行底色随开关切换', (tester) async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    addTearDown(settings.dispose);
    await settings.loaded;

    final theme = buildLightThemeForScheme(
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF4D5C92),
        brightness: Brightness.light,
      ),
      layeredSurfaces: true,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: ToolsSheetRow(icon: Lucide.Plus, label: 'Row'),
          ),
        ),
      ),
    );

    final colors = theme.extension<AppSemanticColors>()!;
    IosCardPress tile() =>
        tester.widget<IosCardPress>(find.byType(IosCardPress));

    expect(settings.useLayeredSheetTiles, isTrue);
    expect(tile().baseColor, colors.surfaceCardFill);

    await settings.setUseLayeredSheetTiles(false);
    await tester.pumpAndSettle();

    expect(tile().baseColor, Colors.transparent);
  });
}
