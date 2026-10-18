import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Shift [base] in HCT tone space, keeping hue and chroma.
Color shiftTone(Color base, double delta) {
  final hct = Hct.fromInt(base.toARGB32());
  return Color(
    Hct.from(hct.hue, hct.chroma, (hct.tone + delta).clamp(0.0, 100.0)).toInt(),
  );
}

/// HCT tone of [color], 0–100.
double surfaceTone(Color color) => Hct.fromInt(color.toARGB32()).tone;

/// Set HCT tone while keeping hue and chroma of [base].
Color atTone(Color base, double tone) {
  final hct = Hct.fromInt(base.toARGB32());
  return Color(Hct.from(hct.hue, hct.chroma, tone.clamp(0.0, 100.0)).toInt());
}

/// Interpolate HCT tone from [from] toward [to], keeping [from]'s hue+chroma.
Color lerpTone(Color from, Color to, double t) {
  return atTone(
    from,
    surfaceTone(from) + (surfaceTone(to) - surfaceTone(from)) * t,
  );
}

/// 调色板声明的 `surface` 是卡片；浅色模式下页面是它往下压 4 级（纯白背景跳过）。
/// 所有语义色与 `surfaceContainer*` 角色都基于改写后的**页面** `ColorScheme.surface`。
///
/// 包含两类东西：
/// - 底色：页面、卡片、页面上的填充、卡片上的填充、五个容器角色；
/// - 线色：细线、卡片边框、输入框边框、强调边框。
///
/// 线色取自本仓库自己的浓度（比上游深），不随分层变化；字段比上游多两个
/// （`cardBorder`／`fieldBorder`），因为本仓库把“卡片边框”与“输入框边框”分开用。
class SurfaceLadder {
  const SurfaceLadder({
    required this.page,
    required this.card,
    required this.surfaceFill,
    required this.surfaceCardFill,
    required this.hairline,
    required this.hairlineStrong,
    required this.cardBorder,
    required this.fieldBorder,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
  });

  final Color page;
  final Color card;
  final Color surfaceFill;
  final Color surfaceCardFill;

  /// 极淡的细线（助手编辑页、语音控件这些地方的容器描边）。
  final Color hairline;

  /// 强调卡片的边框。
  final Color hairlineStrong;

  /// 普通分区卡片的边框。
  final Color cardBorder;

  /// 卡片里输入框的边框。
  final Color fieldBorder;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;

  factory SurfaceLadder.fromScheme(ColorScheme cs, {bool layered = false}) {
    final page = cs.surface;
    final dark = cs.brightness == Brightness.dark;
    // 线色与分层无关：两种模式取同一组值（本仓库自己的浓度）。
    final hairline = cs.outlineVariant.withValues(alpha: dark ? 0.12 : 0.08);
    final hairlineStrong = cs.outlineVariant.withValues(alpha: 0.45);
    final cardBorder = cs.outlineVariant.withValues(alpha: 0.22);
    final fieldBorder = cs.outlineVariant.withValues(alpha: 0.28);

    if (!layered) {
      const white = Color(0xFFFFFFFF);
      const black = Color(0xFF000000);
      Color over(Color c, double a) =>
          Color.alphaBlend(c.withValues(alpha: a), page);
      final card = dark
          ? Color.alphaBlend(white.withValues(alpha: 0.10), page)
          : Color.alphaBlend(white.withValues(alpha: 0.96), page);
      final surfaceFill = Color.alphaBlend(
        cs.onSurface.withValues(alpha: dark ? 0.16 : 0.05),
        page,
      );
      return SurfaceLadder(
        page: page,
        card: card,
        surfaceFill: surfaceFill,
        surfaceCardFill: surfaceFill,
        hairline: hairline,
        hairlineStrong: hairlineStrong,
        cardBorder: cardBorder,
        fieldBorder: fieldBorder,
        surfaceContainerLowest: dark ? over(black, 0.28) : over(white, 0.72),
        surfaceContainerLow: dark ? over(white, 0.03) : over(white, 0.55),
        surfaceContainer: dark ? over(white, 0.045) : over(white, 0.35),
        surfaceContainerHigh: dark ? over(white, 0.06) : over(white, 0.85),
        surfaceContainerHighest: dark
            ? over(white, 0.09)
            : over(cs.onSurface, 0.05),
      );
    }

    final Color card;
    if (dark) {
      card = shiftTone(page, 11.0);
    } else {
      final headroom = 100.0 - surfaceTone(page);
      card = headroom >= 4.5 ? shiftTone(page, 4.0) : shiftTone(page, -3.5);
    }

    final surfaceCardFill = shiftTone(card, dark ? 9.0 : -3.2);
    final surfaceFill = shiftTone(page, dark ? 9.0 : -2.5);

    if (dark) {
      return SurfaceLadder(
        page: page,
        card: card,
        surfaceFill: surfaceFill,
        surfaceCardFill: surfaceCardFill,
        hairline: hairline,
        hairlineStrong: hairlineStrong,
        cardBorder: cardBorder,
        fieldBorder: fieldBorder,
        surfaceContainerLowest: shiftTone(page, -3.0),
        surfaceContainerLow: shiftTone(page, 4.0),
        surfaceContainer: shiftTone(page, 7.0),
        surfaceContainerHigh: shiftTone(page, 11.0),
        surfaceContainerHighest: shiftTone(page, 14.0),
      );
    }

    return SurfaceLadder(
      page: page,
      card: card,
      surfaceFill: surfaceFill,
      surfaceCardFill: surfaceCardFill,
      hairline: hairline,
      hairlineStrong: hairlineStrong,
      cardBorder: cardBorder,
      fieldBorder: fieldBorder,
      surfaceContainerLowest: atTone(page, 100.0),
      surfaceContainerLow: lerpTone(page, card, 0.50),
      surfaceContainer: lerpTone(page, card, 0.75),
      surfaceContainerHigh: card,
      surfaceContainerHighest: surfaceFill,
    );
  }
}
