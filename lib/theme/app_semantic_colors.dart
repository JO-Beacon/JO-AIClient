import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'surface_ladder.dart';

/// 在 [ColorScheme] 中没有专用角色的语义颜色。
///
/// 所有值都由当前 [ColorScheme] 派生或与之协调，因此自定义或种子生成的主题
/// 也能自动获得合适的颜色。
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color surfaceFill;
  final Color surfaceCard;

  /// 放在卡片上的输入框／搜索框底色。分层模式下比卡片再暗（浅色）或再亮（深色）一档，
  /// 不分层时与 [surfaceFill] 相同。
  final Color surfaceCardFill;
  final Color hairline;

  /// 强调卡片的边框。
  final Color hairlineStrong;

  /// 普通分区卡片的边框。
  final Color cardBorder;

  /// 卡片里输入框的边框。
  final Color fieldBorder;
  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color searchHighlight;
  final List<Color> chartSeries;
  final bool layered;

  const AppSemanticColors({
    required this.surfaceFill,
    required this.surfaceCard,
    required this.surfaceCardFill,
    required this.hairline,
    required this.hairlineStrong,
    required this.cardBorder,
    required this.fieldBorder,
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.searchHighlight,
    required this.chartSeries,
    this.layered = false,
  });

  /// 对话框／面板／菜单的填充色。
  ///
  /// 分层模式落在较亮的卡片层；传统模式沿用页面 [ColorScheme.surface]，
  /// 使浮层与旧观感一致。
  Color overlaySurface(ColorScheme scheme) =>
      layered ? surfaceCard : scheme.surface;

  /// 用于输入框、标签、小卡片和标签容器的柔和填充色。
  /// 具体取值由 [SurfaceLadder] 给出：不分层时把文字色按 5%（浅）／16%（深）
  /// 叠到页面底色上；分层时按 HCT 色阶下移一档。
  ///
  /// 线色（[hairline]、[hairlineStrong]、[cardBorder]、[fieldBorder]）也从阶梯取。
  /// 它们的值是本仓库自己的浓度（比上游深），且不随分层变化。

  factory AppSemanticColors.light(ColorScheme cs, {bool layered = false}) {
    const successBase = Color(0xFF2E7D32);
    const warningBase = Color(0xFFF57C00);
    final ladder = SurfaceLadder.fromScheme(cs, layered: layered);
    return AppSemanticColors(
      surfaceFill: ladder.surfaceFill,
      surfaceCard: ladder.card,
      surfaceCardFill: ladder.surfaceCardFill,
      hairline: ladder.hairline,
      hairlineStrong: ladder.hairlineStrong,
      cardBorder: ladder.cardBorder,
      fieldBorder: ladder.fieldBorder,
      success: successBase.harmonizeWith(cs.primary),
      successContainer: const Color(0xFFA5D6A7).harmonizeWith(cs.primary),
      onSuccessContainer: const Color(0xFF1B5E20),
      warning: warningBase.harmonizeWith(cs.primary),
      warningContainer: const Color(0xFFFFE0B2).harmonizeWith(cs.primary),
      onWarningContainer: const Color(0xFF4E2600),
      searchHighlight: const Color(0xFFFFD700).withValues(alpha: 0.55),
      chartSeries: const [
        Color(0xFF2563EB),
        Color(0xFF0F8F83),
        Color(0xFFEA580C),
        Color(0xFF8B5CF6),
        Color(0xFFE11D48),
        Color(0xFF16A34A),
        Color(0xFFCA8A04),
        Color(0xFF0891B2),
      ],
      layered: layered,
    );
  }

  factory AppSemanticColors.dark(ColorScheme cs, {bool layered = false}) {
    const successBase = Color(0xFF81C784);
    const warningBase = Color(0xFFFFB74D);
    final ladder = SurfaceLadder.fromScheme(cs, layered: layered);
    return AppSemanticColors(
      surfaceFill: ladder.surfaceFill,
      surfaceCard: ladder.card,
      surfaceCardFill: ladder.surfaceCardFill,
      hairline: ladder.hairline,
      hairlineStrong: ladder.hairlineStrong,
      cardBorder: ladder.cardBorder,
      fieldBorder: ladder.fieldBorder,
      success: successBase.harmonizeWith(cs.primary),
      successContainer: const Color(0xFF1B5E20).harmonizeWith(cs.primary),
      onSuccessContainer: const Color(0xFFC8E6C9),
      warning: warningBase.harmonizeWith(cs.primary),
      warningContainer: const Color(0xFF8D4E00).harmonizeWith(cs.primary),
      onWarningContainer: const Color(0xFFFFE8CC),
      searchHighlight: const Color(0xFFB8860B).withValues(alpha: 0.55),
      chartSeries: const [
        Color(0xFF60A5FA),
        Color(0xFF5EEAD4),
        Color(0xFFFB923C),
        Color(0xFFA78BFA),
        Color(0xFFFB7185),
        Color(0xFF86EFAC),
        Color(0xFFFACC15),
        Color(0xFF67E8F9),
      ],
      layered: layered,
    );
  }

  @override
  AppSemanticColors copyWith({
    Color? surfaceFill,
    Color? surfaceCard,
    Color? surfaceCardFill,
    Color? hairline,
    Color? hairlineStrong,
    Color? cardBorder,
    Color? fieldBorder,
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? searchHighlight,
    List<Color>? chartSeries,
    bool? layered,
  }) {
    return AppSemanticColors(
      surfaceFill: surfaceFill ?? this.surfaceFill,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      surfaceCardFill: surfaceCardFill ?? this.surfaceCardFill,
      hairline: hairline ?? this.hairline,
      hairlineStrong: hairlineStrong ?? this.hairlineStrong,
      cardBorder: cardBorder ?? this.cardBorder,
      fieldBorder: fieldBorder ?? this.fieldBorder,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      searchHighlight: searchHighlight ?? this.searchHighlight,
      chartSeries: chartSeries ?? this.chartSeries,
      layered: layered ?? this.layered,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    final len = chartSeries.length < other.chartSeries.length
        ? chartSeries.length
        : other.chartSeries.length;
    return AppSemanticColors(
      surfaceFill: Color.lerp(surfaceFill, other.surfaceFill, t)!,
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t)!,
      surfaceCardFill: Color.lerp(surfaceCardFill, other.surfaceCardFill, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hairlineStrong: Color.lerp(hairlineStrong, other.hairlineStrong, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      fieldBorder: Color.lerp(fieldBorder, other.fieldBorder, t)!,
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      searchHighlight: Color.lerp(searchHighlight, other.searchHighlight, t)!,
      chartSeries: List.generate(
        len,
        (i) => Color.lerp(chartSeries[i], other.chartSeries[i], t)!,
      ),
      layered: t < 0.5 ? layered : other.layered,
    );
  }
}

extension AppSemanticColorsX on BuildContext {
  /// 当前环境中的 [AppSemanticColors]。当扩展未挂载时（例如只 pump 了一个
  /// 普通 MaterialApp 的 widget 测试），会回退为从环境中的 [ColorScheme] 派生。
  AppSemanticColors get appColors {
    final theme = Theme.of(this);
    final ext = theme.extension<AppSemanticColors>();
    if (ext != null) return ext;
    return theme.brightness == Brightness.dark
        ? AppSemanticColors.dark(theme.colorScheme)
        : AppSemanticColors.light(theme.colorScheme);
  }

  /// 对话框／面板／菜单。见 [AppSemanticColors.overlaySurface]。
  Color get overlaySurface =>
      appColors.overlaySurface(Theme.of(this).colorScheme);
}
