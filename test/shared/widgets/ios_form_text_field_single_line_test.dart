import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/theme/app_semantic_colors.dart';
import 'package:Kelivo/theme/theme_factory.dart';
import 'package:Kelivo/shared/widgets/ios_form_text_field.dart';

/// 单行输入框的基线契约：文字按 1.0 行盒居中，不靠 1.15 行高“凑”。
/// 这条来自上游统一模型编辑弹窗时的修正（`b7cc32b2`），此前本仓库没跟。
void main() {
  Future<TextField> pumpField(
    WidgetTester tester, {
    required int maxLines,
  }) async {
    final controller = TextEditingController(text: 'value');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IosFormTextField(
            label: 'Label',
            controller: controller,
            maxLines: maxLines,
          ),
        ),
      ),
    );
    return tester.widget<TextField>(find.byType(TextField));
  }

  testWidgets('单行输入框用 1.0 行高和强制 strut', (tester) async {
    final field = await pumpField(tester, maxLines: 1);

    expect(field.style?.height, 1.0);
    expect(field.strutStyle?.forceStrutHeight, isTrue);
    expect(field.strutStyle?.height, 1.0);
    expect(field.strutStyle?.fontSize, 15);
    // 单行不能折叠内边距，否则内容区高度会小于 strut。
    expect(field.decoration?.isCollapsed, isFalse);
  });

  testWidgets('多行输入框保持 1.25 行高、不加 strut', (tester) async {
    final field = await pumpField(tester, maxLines: 4);

    expect(field.style?.height, 1.25);
    expect(field.strutStyle, isNull);
    expect(field.decoration?.isCollapsed, isTrue);
  });

  testWidgets('输入框底色用“卡片上的输入框”那一档', (tester) async {
    final controller = TextEditingController(text: 'value');
    addTearDown(controller.dispose);
    final theme = buildLightThemeForScheme(
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF4D5C92),
        brightness: Brightness.light,
      ),
      layeredSurfaces: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: IosFormTextField(label: 'Label', controller: controller),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    final colors = Theme.of(
      tester.element(find.byType(IosFormTextField)),
    ).extension<AppSemanticColors>()!;
    expect(colors.surfaceCardFill, isNot(colors.surfaceFill));

    // 底色画在包裹输入框的容器上，而不是 InputDecoration 上。
    final fills = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(IosFormTextField),
            matching: find.byType(Container),
          ),
        )
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .whereType<Color>();
    expect(fills, contains(colors.surfaceCardFill));
    expect(field.decoration?.fillColor, isNull);
  });
}
