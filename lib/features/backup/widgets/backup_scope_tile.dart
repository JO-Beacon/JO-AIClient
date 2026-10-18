import 'package:flutter/material.dart';

import '../../../core/models/backup_scope.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../theme/app_font_weights.dart';

/// 备份/恢复范围选择：一行摘要，点开逐类勾选。
class BackupScopeTile extends StatelessWidget {
  const BackupScopeTile({
    super.key,
    required this.scope,
    required this.onChanged,
    this.desktop = false,
  });

  final BackupScope scope;
  final ValueChanged<BackupScope> onChanged;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final selected = BackupCategory.values.where(scope.includes).length;
    final total = BackupCategory.values.length;
    return IosCardPress(
      key: const ValueKey('backup-scope-tile'),
      onTap: () async {
        final next = desktop
            ? await showDialog<BackupScope>(
                context: context,
                builder: (_) => _ScopeDialog(scope: scope),
              )
            : await showModalBottomSheet<BackupScope>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _ScopeDialog(scope: scope),
              );
        if (next != null) onChanged(next);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Lucide.Database, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.backupScopeTitle,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: AppFontWeights.regular,
                  color: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.backupScopeSummary(selected, total),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Lucide.ChevronRight,
              size: 16,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScopeDialog extends StatefulWidget {
  const _ScopeDialog({required this.scope});

  final BackupScope scope;

  @override
  State<_ScopeDialog> createState() => _ScopeDialogState();
}

class _ScopeDialogState extends State<_ScopeDialog> {
  late BackupScope _scope = widget.scope;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.backupScopeTitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: AppFontWeights.semibold,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(_scope),
                    child: Text(l10n.backupScopeDone),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: BackupCategory.values.length,
                itemBuilder: (context, index) {
                  final category = BackupCategory.values[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _label(l10n, category),
                            style: TextStyle(fontSize: 14, color: cs.onSurface),
                          ),
                        ),
                        IosSwitch(
                          value: _scope.includes(category),
                          onChanged: (value) => setState(() {
                            _scope = _scope.withCategory(category, value);
                          }),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

String _label(AppLocalizations l10n, BackupCategory category) =>
    switch (category) {
      BackupCategory.chats => l10n.backupPageChatsLabel,
      BackupCategory.files => l10n.backupPageFilesLabel,
      BackupCategory.assistants => l10n.backupScopeAssistants,
      BackupCategory.providers => l10n.backupScopeProviders,
      BackupCategory.mcp => l10n.backupScopeMcp,
      BackupCategory.skills => l10n.backupScopeSkills,
      BackupCategory.worldBooks => l10n.backupScopeWorldBooks,
      BackupCategory.memories => l10n.backupScopeMemories,
      BackupCategory.quickPhrases => l10n.backupScopeQuickPhrases,
      BackupCategory.instructions => l10n.backupScopeInstructions,
      BackupCategory.workspaces => l10n.backupScopeWorkspaces,
      BackupCategory.searchServices => l10n.backupScopeSearchServices,
      BackupCategory.speechServices => l10n.backupScopeSpeechServices,
      BackupCategory.settings => l10n.backupScopeSettings,
    };
