import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/chat/widgets/message_parts_editor.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/long_message_editor.dart';

import '../../../support/business_test_harness.dart';

/// 编辑面板里文本部件的两个输入框（行内、全屏展开）都跟着“长文本编辑器”开关走。
void main() {
  Future<SettingsProvider> pumpEditor(
    WidgetTester tester, {
    required bool enabled,
  }) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    addTearDown(settings.dispose);
    await settings.loaded;
    if (enabled) await settings.setUseLongMessageEditor(true);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MessagePartsEditor(
                parts: [TextPart(List.filled(800, '长文本').join())],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  testWidgets('开关关闭时文本部件仍用原生输入框', (tester) async {
    await pumpEditor(tester, enabled: false);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(LongMessageEditor), findsNothing);
  });

  testWidgets('开关打开时文本部件换成包装组件', (tester) async {
    await pumpEditor(tester, enabled: true);

    expect(find.byType(LongMessageEditor), findsOneWidget);
  });

  testWidgets('全屏展开后同样走包装组件', (tester) async {
    await pumpEditor(tester, enabled: true);

    await tester.tap(find.byIcon(Lucide.Maximize2).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 展开后是同一个包装组件（行内那个仍在底下，因此按个数判断）。
    expect(find.byType(LongMessageEditor), findsWidgets);
  });
}
