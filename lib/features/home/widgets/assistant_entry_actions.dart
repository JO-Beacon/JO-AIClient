import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../controllers/chat_actions.dart';
import '../../../core/providers/assistant_group_provider.dart';
import '../../../desktop/desktop_context_menu.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/dialogs/assistant_delete_confirm_dialog.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../assistant/pages/assistant_settings_edit_page.dart';
import '../../assistant/pages/assistant_groups_manager_page.dart';
import '../../assistant/widgets/assistant_groups_manager_dialog.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

class AssistantEntryActions {
  const AssistantEntryActions._();

  /// “未指定助手”是内置条目：可查看、可接收会话，但不能改名或删除。
  static bool _isUnassigned(Assistant assistant) =>
      assistant.id == AssistantProvider.unassignedAssistantId;

  static bool get _isDesktopPlatform =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  static void openAssistantSettings(
    BuildContext context,
    String assistantId, {
    VoidCallback? beforeAction,
  }) {
    beforeAction?.call();
    if (_isDesktopPlatform) {
      showAssistantDesktopDialog(context, assistantId: assistantId);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AssistantSettingsEditPage(assistantId: assistantId),
      ),
    );
  }

  static Future<void> showAssistantItemMenu({
    required BuildContext context,
    required Assistant assistant,
    Offset? globalPosition,
    VoidCallback? beforeAction,
    VoidCallback? onSelect,
  }) async {
    // 未指定助手是内置条目：不提供复制、多选、分组、改名或删除。
    if (_isUnassigned(assistant)) return;
    if (_isDesktopPlatform) {
      if (globalPosition == null) return;
      await _showAssistantItemMenuDesktop(
        context: context,
        assistant: assistant,
        globalPosition: globalPosition,
        beforeAction: beforeAction,
        onSelect: onSelect,
      );
      return;
    }
    await _showAssistantItemMenuMobile(
      context: context,
      assistant: assistant,
      beforeAction: beforeAction,
      onSelect: onSelect,
    );
  }

  static Future<void> _duplicateAssistantFromMenu(
    BuildContext context,
    Assistant assistant,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final newId = await context.read<AssistantProvider>().duplicateAssistant(
      assistant.id,
      l10n: l10n,
      insertAtTop: context.read<SettingsProvider>().insertNewAssistantAtTop,
    );
    if (!context.mounted || newId == null) return;
    showAppSnackBar(
      context,
      message: l10n.assistantSettingsCopySuccess,
      type: NotificationType.success,
    );
  }

  static Future<void> _showAssistantItemMenuDesktop({
    required BuildContext context,
    required Assistant assistant,
    required Offset globalPosition,
    VoidCallback? beforeAction,
    VoidCallback? onSelect,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final groupProvider = context.read<AssistantGroupProvider>();
    final hasGroup = groupProvider.groupOfAssistant(assistant.id) != null;

    await showDesktopContextMenuAt(
      context,
      globalPosition: globalPosition,
      items: [
        if (!_isUnassigned(assistant))
          DesktopContextMenuItem(
            icon: Lucide.Pencil,
            label: l10n.assistantGroupsContextMenuEditAssistant,
            onTap: () => openAssistantSettings(
              context,
              assistant.id,
              beforeAction: beforeAction,
            ),
          ),
        if (onSelect != null)
          DesktopContextMenuItem(
            icon: Lucide.CheckSquare,
            label: l10n.assistantSelectionActionSelect,
            onTap: () {
              beforeAction?.call();
              onSelect.call();
            },
          ),
        DesktopContextMenuItem(
          icon: Lucide.Copy,
          label: l10n.assistantSettingsCopyButton,
          onTap: () async {
            beforeAction?.call();
            await _duplicateAssistantFromMenu(context, assistant);
          },
        ),
        if (hasGroup)
          DesktopContextMenuItem(
            icon: Lucide.Eraser,
            label: l10n.assistantGroupsRemoveFromGroup,
            onTap: () async {
              beforeAction?.call();
              await context
                  .read<AssistantGroupProvider>()
                  .unassignAssistantFromGroup(assistant.id);
            },
          ),
        DesktopContextMenuItem(
          icon: Lucide.Bookmark,
          label: l10n.assistantGroupsContextMenuManageGroups,
          onTap: () async {
            beforeAction?.call();
            await showAssistantGroupsManagerDialog(
              context,
              assistantId: assistant.id,
            );
          },
        ),
        if (!_isUnassigned(assistant))
          DesktopContextMenuItem(
            icon: Lucide.Trash2,
            label: l10n.assistantGroupsContextMenuDeleteAssistant,
            danger: true,
            onTap: () async {
              beforeAction?.call();
              await _deleteAssistant(context, assistant);
            },
          ),
      ],
    );
  }

  static Future<void> _showAssistantItemMenuMobile({
    required BuildContext context,
    required Assistant assistant,
    VoidCallback? beforeAction,
    VoidCallback? onSelect,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final groupProvider = context.read<AssistantGroupProvider>();
    final hasGroup = groupProvider.groupOfAssistant(assistant.id) != null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;

        Widget row(
          String text,
          IconData icon,
          VoidCallback onTap, {
          bool danger = false,
        }) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SizedBox(
              height: 48,
              child: IosCardPress(
                borderRadius: BorderRadius.circular(14),
                baseColor: cs.surface,
                duration: const Duration(milliseconds: 220),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onTap();
                },
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: danger ? cs.error : cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: AppFontWeights.medium,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isUnassigned(assistant))
                  row(
                    l10n.assistantGroupsContextMenuEditAssistant,
                    Lucide.Pencil,
                    () => openAssistantSettings(
                      context,
                      assistant.id,
                      beforeAction: beforeAction,
                    ),
                  ),
                if (onSelect != null)
                  row(
                    l10n.assistantSelectionActionSelect,
                    Lucide.CheckSquare,
                    () {
                      beforeAction?.call();
                      onSelect.call();
                    },
                  ),
                row(l10n.assistantSettingsCopyButton, Lucide.Copy, () async {
                  beforeAction?.call();
                  await _duplicateAssistantFromMenu(context, assistant);
                }),
                if (hasGroup)
                  row(
                    l10n.assistantGroupsRemoveFromGroup,
                    Lucide.Eraser,
                    () async {
                      beforeAction?.call();
                      await context
                          .read<AssistantGroupProvider>()
                          .unassignAssistantFromGroup(assistant.id);
                    },
                  ),
                row(
                  l10n.assistantGroupsContextMenuManageGroups,
                  Lucide.Bookmark,
                  () async {
                    beforeAction?.call();
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AssistantGroupsManagerPage(
                          assistantId: assistant.id,
                        ),
                      ),
                    );
                  },
                ),
                if (!_isUnassigned(assistant))
                  row(
                    l10n.assistantGroupsContextMenuDeleteAssistant,
                    Lucide.Trash2,
                    () async {
                      beforeAction?.call();
                      await _deleteAssistant(context, assistant);
                    },
                    danger: true,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> _deleteAssistant(
    BuildContext context,
    Assistant assistant,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final assistantProvider = context.read<AssistantProvider>();
    final groupProvider = context.read<AssistantGroupProvider>();
    final choice = await showAssistantDeleteConfirmDialog(
      context,
      title: l10n.assistantSettingsDeleteDialogTitle,
      content: l10n.assistantSettingsDeleteDialogContent,
      keepConversationsOption: l10n.assistantDeleteConversationsOption,
      cancelLabel: l10n.assistantSettingsDeleteDialogCancel,
      confirmLabel: l10n.assistantSettingsDeleteDialogConfirm,
    );

    if (!context.mounted || choice == null) return;
    await ChatActions.cancelActiveGenerationsForAssistant(assistant.id);
    if (!context.mounted) return;
    final ok = await assistantProvider.deleteAssistant(
      assistant.id,
      deleteConversations: choice.deleteConversations,
    );
    if (!context.mounted) return;

    if (!ok) {
      showAppSnackBar(
        context,
        message: l10n.assistantSettingsAtLeastOneAssistantRequired,
        type: NotificationType.warning,
      );
      return;
    }

    try {
      await groupProvider.unassignAssistantFromGroup(assistant.id);
    } catch (_) {}
  }
}
