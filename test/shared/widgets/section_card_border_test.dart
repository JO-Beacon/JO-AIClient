import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/shared/widgets/section_card.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';
import 'package:Kelivo/theme/theme_factory.dart';

/// 分区卡片的边框：普通用 `cardBorder`（22%），强调用 `hairlineStrong`（45%）。
/// 这两个值来自本仓库自己的阶梯，不随分层变化。
void main() {
  Future<AppSemanticColors> pumpCards(
    WidgetTester tester, {
    required bool layered,
  }) async {
    final theme = buildLightThemeForScheme(
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF4D5C92),
        brightness: Brightness.light,
      ),
      layeredSurfaces: layered,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Column(
            children: [
              SectionCard(
                key: ValueKey('standard'),
                child: SizedBox(height: 8),
              ),
              SectionCard(
                key: ValueKey('emphasized'),
                variant: SectionCardVariant.emphasized,
                child: SizedBox(height: 8),
              ),
            ],
          ),
        ),
      ),
    );
    return theme.extension<AppSemanticColors>()!;
  }

  Color borderOf(WidgetTester tester, String key) {
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Container),
          )
          .first,
    );
    final border = (container.decoration as BoxDecoration).border! as Border;
    return border.top.color;
  }

  testWidgets('普通与强调卡片各自用对应的线色', (tester) async {
    final colors = await pumpCards(tester, layered: false);

    expect(borderOf(tester, 'standard'), colors.cardBorder);
    expect(borderOf(tester, 'emphasized'), colors.hairlineStrong);
  });

  testWidgets('分层开关不改变边框浓度', (tester) async {
    final plain = await pumpCards(tester, layered: false);
    final standardPlain = borderOf(tester, 'standard');
    final emphasizedPlain = borderOf(tester, 'emphasized');

    final layered = await pumpCards(tester, layered: true);
    expect(borderOf(tester, 'standard'), standardPlain);
    expect(borderOf(tester, 'emphasized'), emphasizedPlain);
    expect(standardPlain, plain.cardBorder);
    expect(emphasizedPlain, layered.hairlineStrong);
  });
}
