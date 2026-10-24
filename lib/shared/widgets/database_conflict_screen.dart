import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/database/database_name_migration.dart';
import '../../features/settings/widgets/custom_theme_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/ios_tactile.dart';
import '../../shared/widgets/ios_text_button.dart';
import '../../theme/app_font_weights.dart';

/// 启动阶段的阻断式数据库选择。使用应用统一的 showAppDialog 外壳，
/// 不自己画遮罩/对话框。
class DatabaseConflictScreen extends StatefulWidget {
  const DatabaseConflictScreen({
    super.key,
    required this.conflict,
    required this.onChoose,
    required this.onExit,
  });

  final DatabaseConflict conflict;
  final Future<void> Function(DatabaseConflictChoice choice) onChoose;
  final VoidCallback onExit;

  @override
  State<DatabaseConflictScreen> createState() => _DatabaseConflictScreenState();
}

class _DatabaseConflictScreenState extends State<DatabaseConflictScreen> {
  var _presented = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _presented) return;
      _presented = true;
      showAppDialog<void>(
        context,
        dismissible: false,
        maxWidth: 520,
        child: _DatabaseConflictDialog(
          conflict: widget.conflict,
          onChoose: widget.onChoose,
          onExit: widget.onExit,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _DatabaseConflictDialog extends StatefulWidget {
  const _DatabaseConflictDialog({
    required this.conflict,
    required this.onChoose,
    required this.onExit,
  });

  final DatabaseConflict conflict;
  final Future<void> Function(DatabaseConflictChoice choice) onChoose;
  final VoidCallback onExit;

  @override
  State<_DatabaseConflictDialog> createState() =>
      _DatabaseConflictDialogState();
}

class _DatabaseConflictDialogState extends State<_DatabaseConflictDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _choose(DatabaseConflictChoice choice) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onChoose(choice);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppLocalizations.of(
          context,
        )!.databaseConflictQuarantineFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDialogHeader(
          title: l10n.databaseConflictTitle,
          showClose: false,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.databaseConflictBody(
                    widget.conflict.quarantineDirectory.path,
                  ),
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: cs.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 16),
                _DatabaseChoiceCard(
                  key: const ValueKey('database-conflict-current'),
                  file: _mainFile(widget.conflict.currentFiles),
                  label: 'jo_aiclient.db',
                  onTap: _busy
                      ? null
                      : () => _choose(DatabaseConflictChoice.current),
                ),
                const SizedBox(height: 10),
                _DatabaseChoiceCard(
                  key: const ValueKey('database-conflict-legacy'),
                  file: _mainFile(widget.conflict.legacyFiles),
                  label: 'kelivo.db',
                  onTap: _busy
                      ? null
                      : () => _choose(DatabaseConflictChoice.legacy),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(fontSize: 12.5, color: cs.error),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: IosTextButton(
              label: l10n.databaseConflictExit,
              onPressed: _busy ? null : widget.onExit,
            ),
          ),
        ),
      ],
    );
  }

  File _mainFile(List<File> files) => files.firstWhere(
    (file) => !file.path.endsWith('-wal') &&
        !file.path.endsWith('-shm') &&
        !file.path.endsWith('-journal'),
    orElse: () => files.first,
  );
}

class _DatabaseChoiceCard extends StatelessWidget {
  const _DatabaseChoiceCard({
    super.key,
    required this.file,
    required this.label,
    required this.onTap,
  });

  final File file;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final modified = _modified(file);
    final size = _size(file);
    return IosCardPress(
      focusable: true,
      haptics: false,
      baseColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${l10n.databaseConflictModified}: '
                  '${modified ?? l10n.databaseConflictUnreadable}  '
                  '${l10n.databaseConflictSize}: '
                  '${size ?? l10n.databaseConflictUnreadable}',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            l10n.databaseConflictUse,
            style: TextStyle(
              fontSize: 13,
              fontWeight: AppFontWeights.semibold,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }

  static String? _modified(File file) {
    try {
      final time = file.lastModifiedSync().toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      return '${time.year}-${two(time.month)}-${two(time.day)} '
          '${two(time.hour)}:${two(time.minute)}';
    } on FileSystemException {
      return null;
    }
  }

  static String? _size(File file) {
    try {
      final bytes = file.lengthSync();
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) {
        return '${(bytes / 1024).toStringAsFixed(1)} KB';
      }
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } on FileSystemException {
      return null;
    }
  }
}
