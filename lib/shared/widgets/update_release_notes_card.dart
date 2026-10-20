import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/shared/markdown/markdown_with_code_highlight.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';
import 'package:flutter/material.dart';
import 'ios_tactile.dart';

class UpdateReleaseNotesCard extends StatelessWidget {
  const UpdateReleaseNotesCard({
    super.key,
    required this.title,
    required this.notes,
    this.onTap,
    this.haptics = true,
    this.onLinkTap,
  });

  final String title;
  final String notes;
  final VoidCallback? onTap;
  final bool haptics;
  final ValueChanged<String>? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final body = notes.trim();
    final border = BorderSide(
      width: 0.5,
      color: isDark
          ? cs.onSurface.withValues(alpha: 0.06)
          : cs.outlineVariant.withValues(alpha: 0.12),
    );

    return IosCardPress(
      onTap: onTap,
      haptics: haptics,
      baseColor: context.appColors.surfaceCard,
      borderRadius: BorderRadius.circular(12),
      border: Border.fromBorderSide(border),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Lucide.BadgeInfo, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: AppFontWeights.emphasis,
                        color: cs.onSurface,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 12),
                MarkdownWithCodeHighlight(
                  text: body,
                  baseStyle: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: cs.onSurface.withValues(alpha: 0.85),
                    letterSpacing: 0,
                  ),
                  onLinkTap: onLinkTap,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
