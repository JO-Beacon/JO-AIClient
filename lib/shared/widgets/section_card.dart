import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../theme/app_semantic_colors.dart';

enum SectionCardVariant { standard, emphasized }

/// Shared iOS-style section card: one step above the page surface.
///
/// Use [children] for stacked rows or [child] for a single body. Optional
/// [padding], [radius], and [shadow] override the defaults.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.children,
    this.child,
    this.padding,
    this.radius,
    this.variant = SectionCardVariant.standard,
    this.shadow,
    this.dividers = false,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  }) : assert(
         children != null || child != null,
         'Provide either children or child',
       );

  final List<Widget>? children;
  final Widget? child;
  final EdgeInsetsGeometry? padding;
  final double? radius;
  final SectionCardVariant variant;
  final List<BoxShadow>? shadow;
  final bool dividers;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cs = Theme.of(context).colorScheme;
    final emphasized = variant == SectionCardVariant.emphasized;
    final resolvedRadius = radius ?? (emphasized ? 18.0 : 12.0);
    final borderColor = emphasized ? colors.hairlineStrong : colors.cardBorder;
    final resolvedPadding =
        padding ??
        (child != null && children == null
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(vertical: 4));
    final body = children != null
        ? Column(
            crossAxisAlignment: crossAxisAlignment,
            children: [
              for (int i = 0; i < children!.length; i++) ...[
                if (dividers && i > 0)
                  Divider(
                    height: 10,
                    thickness: 0.6,
                    color: cs.outlineVariant.withValues(alpha: 0.18),
                  ),
                children![i],
              ],
            ],
          )
        : child!;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(resolvedRadius),
        border: Border.all(color: borderColor, width: 0.6),
        boxShadow: shadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: resolvedPadding, child: body),
    );
  }
}

/// 面板内操作瓦片的填充色。
///
/// 与上游一致：开着“分层表单瓦片”时用卡片上的输入框那一档底色，
/// 关掉时透明，让磨砂／半透明的面板保持通透。
Color sheetTileColor(BuildContext context) {
  var layered = true;
  try {
    layered = context.watch<SettingsProvider>().useLayeredSheetTiles;
  } catch (_) {}
  return layered ? context.appColors.surfaceCardFill : Colors.transparent;
}

/// 分层瓦片打开时，瓦片之间才画分隔线。
bool showSheetTileDividers(BuildContext context) {
  try {
    return context.watch<SettingsProvider>().useLayeredSheetTiles;
  } catch (_) {
    return true;
  }
}
