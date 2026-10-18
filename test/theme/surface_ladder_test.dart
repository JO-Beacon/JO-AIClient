import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/theme/app_semantic_colors.dart';
import 'package:Kelivo/theme/surface_ladder.dart';
import 'package:Kelivo/theme/theme_factory.dart';

/// 表面阶梯：不分层时与旧算法逐项相同（默认观感不变），
/// 分层时多出“放在卡片上的输入框”那一档，并让卡片浮在页面之上。
void main() {
  final light = ColorScheme.fromSeed(
    seedColor: const Color(0xFF4D5C92),
    brightness: Brightness.light,
  );
  final dark = ColorScheme.fromSeed(
    seedColor: const Color(0xFF4D5C92),
    brightness: Brightness.dark,
  );

  group('不分层', () {
    test('颜色与旧算法逐项相同', () {
      final ladder = SurfaceLadder.fromScheme(light, layered: false);
      Color over(Color c, double a) =>
          Color.alphaBlend(c.withValues(alpha: a), light.surface);

      expect(ladder.surfaceFill, over(light.onSurface, 0.05));
      expect(ladder.card, over(const Color(0xFFFFFFFF), 0.96));
      // 没有第三档：卡片上的输入框与页面上的相同。
      expect(ladder.surfaceCardFill, ladder.surfaceFill);
    });

    test('深色模式的填充与卡片也与旧算法相同', () {
      final ladder = SurfaceLadder.fromScheme(dark, layered: false);
      Color over(Color c, double a) =>
          Color.alphaBlend(c.withValues(alpha: a), dark.surface);

      expect(ladder.surfaceFill, over(dark.onSurface, 0.16));
      expect(ladder.card, over(const Color(0xFFFFFFFF), 0.10));
      expect(ladder.surfaceCardFill, ladder.surfaceFill);
    });
  });

  group('分层', () {
    test('浅色：卡片与页面拉开一档，卡片里的输入框比卡片再低一档', () {
      final ladder = SurfaceLadder.fromScheme(light, layered: true);

      expect(ladder.card, isNot(ladder.page));
      expect(
        surfaceTone(ladder.surfaceCardFill),
        lessThan(surfaceTone(ladder.card)),
      );
      expect(ladder.surfaceCardFill, isNot(ladder.surfaceFill));
    });

    test('浅色页面还有亮度余量时，卡片往上抬 4 级', () {
      // 近白的页面没有余量：上游会把卡片往下压，而不是硬抬。
      final darkerPage = light.copyWith(surface: const Color(0xFFEDEBF2));
      final ladder = SurfaceLadder.fromScheme(darkerPage, layered: true);

      expect(
        surfaceTone(ladder.card),
        closeTo(surfaceTone(ladder.page) + 4, 0.51),
      );
    });

    test('深色：卡片与卡片里的输入框都比页面亮', () {
      final ladder = SurfaceLadder.fromScheme(dark, layered: true);

      expect(surfaceTone(ladder.card), greaterThan(surfaceTone(ladder.page)));
      expect(
        surfaceTone(ladder.surfaceCardFill),
        greaterThan(surfaceTone(ladder.card)),
      );
      expect(ladder.surfaceCardFill, isNot(ladder.surfaceFill));
    });
  });

  group('线色（本仓库自己的浓度，不随分层变化）', () {
    test('四个字段等于原有浓度', () {
      for (final layered in [false, true]) {
        final ladder = SurfaceLadder.fromScheme(light, layered: layered);
        expect(ladder.hairline, light.outlineVariant.withValues(alpha: 0.08));
        expect(ladder.cardBorder, light.outlineVariant.withValues(alpha: 0.22));
        expect(
          ladder.fieldBorder,
          light.outlineVariant.withValues(alpha: 0.28),
        );
        expect(
          ladder.hairlineStrong,
          light.outlineVariant.withValues(alpha: 0.45),
        );
      }
      // 深色细线更深一点，其余三档两种模式相同。
      final darkLadder = SurfaceLadder.fromScheme(dark, layered: true);
      expect(darkLadder.hairline, dark.outlineVariant.withValues(alpha: 0.12));
      expect(
        darkLadder.cardBorder,
        dark.outlineVariant.withValues(alpha: 0.22),
      );
    });

    test('AppSemanticColors 带出同一组线色', () {
      for (final layered in [false, true]) {
        final colors = AppSemanticColors.light(light, layered: layered);
        expect(colors.hairline, light.outlineVariant.withValues(alpha: 0.08));
        expect(colors.cardBorder, light.outlineVariant.withValues(alpha: 0.22));
        expect(
          colors.fieldBorder,
          light.outlineVariant.withValues(alpha: 0.28),
        );
        expect(
          colors.hairlineStrong,
          light.outlineVariant.withValues(alpha: 0.45),
        );
      }
    });
  });

  group('AppSemanticColors', () {
    test('两种模式都带出第三档', () {
      final colors = AppSemanticColors.light(light, layered: true);
      expect(colors.surfaceCardFill, isNot(colors.surfaceFill));
    });

    test('copyWith 与 lerp 都保留新字段', () {
      final colors = AppSemanticColors.light(light, layered: true);
      final copy = colors.copyWith(surfaceCardFill: const Color(0xFF123456));
      expect(copy.surfaceCardFill, const Color(0xFF123456));

      final mid = colors.lerp(AppSemanticColors.dark(dark, layered: true), 0.5);
      expect(mid.surfaceCardFill, isNot(colors.surfaceCardFill));
    });
  });

  group('主题构建', () {
    test('分层时浅色页面底色往下压 4 级', () {
      final theme = buildLightThemeForScheme(light, layeredSurfaces: true);
      expect(
        surfaceTone(theme.colorScheme.surface),
        closeTo(surfaceTone(light.surface) - 4, 0.51),
      );
    });

    test('纯白背景下页面仍是纯白，不往下压', () {
      final theme = buildLightThemeForScheme(
        light,
        pureBackground: true,
        layeredSurfaces: true,
      );
      expect(theme.colorScheme.surface, const Color(0xFFFFFFFF));
    });

    test('分层时容器角色来自阶梯，不再是 Material 默认值', () {
      final theme = buildLightThemeForScheme(light, layeredSurfaces: true);
      final ladder = SurfaceLadder.fromScheme(
        theme.colorScheme.copyWith(surface: theme.colorScheme.surface),
        layered: true,
      );
      expect(theme.colorScheme.surfaceContainer, ladder.surfaceContainer);
      expect(
        theme.colorScheme.surfaceContainerHigh,
        ladder.surfaceContainerHigh,
      );
    });
  });
}
