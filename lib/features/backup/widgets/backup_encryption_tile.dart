import 'package:flutter/material.dart';

import '../../../core/services/backup/joaiclient_archive.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/responsive/screen_type_helper.dart';
import '../../../shared/widgets/form_sheet.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../settings/widgets/custom_theme_widgets.dart';

/// 密码只存在备份页面的 State 里，不写入设置或备份。
class BackupEncryptionTile extends StatelessWidget {
  const BackupEncryptionTile({
    super.key,
    required this.password,
    required this.onChanged,
  });

  final String? password;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Future<void> change(bool enabled) async {
      if (onChanged == null) return;
      if (!enabled) {
        onChanged!(null);
        return;
      }
      final value = await showBackupPasswordDialog(context, creating: true);
      if (context.mounted && value != null) onChanged!(value);
    }

    return IosNavRow(
      icon: Lucide.Lock,
      label: l10n.backupEncryptionTitle,
      subtitle: password == null
          ? l10n.backupEncryptionOffHint
          : l10n.backupEncryptionOnHint,
      subtitleMaxLines: null,
      onTap: onChanged == null ? null : () => change(password == null),
      trailing: IosSwitch(
        key: const ValueKey('backup-encryption-switch'),
        semanticLabel: l10n.backupEncryptionTitle,
        value: password != null,
        onChanged: onChanged == null ? null : change,
      ),
    );
  }
}

JoaiclientPasswordPrompt backupPasswordPrompt(BuildContext context) {
  return ({required retry}) async {
    if (!context.mounted) return null;
    return showBackupPasswordDialog(context, retry: retry);
  };
}

Future<String?> showBackupPasswordDialog(
  BuildContext context, {
  bool creating = false,
  bool retry = false,
}) {
  final desktop = ResponsiveHelper.isDesktop(context);
  final editor = _BackupPasswordEditor(creating: creating, retry: retry);
  if (desktop) {
    return showAppDialog<String>(context, maxWidth: 400, child: editor);
  }
  return showFormSheet<String>(
    context,
    builder: (_) => editor,
  );
}

class _BackupPasswordEditor extends StatefulWidget {
  const _BackupPasswordEditor({required this.creating, required this.retry});

  final bool creating;
  final bool retry;

  @override
  State<_BackupPasswordEditor> createState() => _BackupPasswordEditorState();
}

class _BackupPasswordEditorState extends State<_BackupPasswordEditor> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _visible = false;

  bool get _valid =>
      _password.text.isNotEmpty &&
      (!widget.creating || _password.text == _confirmation.text);

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    if (_valid) Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final children = <Widget>[
      IosFormTextField(
        key: const ValueKey('backup-password'),
        label: l10n.backupEncryptionPassword,
        controller: _password,
        inlineLabel: false,
        outerPadding: EdgeInsets.zero,
        obscureText: !_visible,
        autocorrect: false,
        enableSuggestions: false,
        autofocus: true,
        textInputAction: widget.creating
            ? TextInputAction.next
            : TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (!widget.creating) _submit();
        },
        suffix: IosIconButton(
          key: const ValueKey('backup-password-visibility'),
          icon: _visible ? Lucide.EyeOff : Lucide.Eye,
          size: 18,
          minSize: 36,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          tooltip: _visible
              ? l10n.backupEncryptionHidePassword
              : l10n.backupEncryptionShowPassword,
          semanticLabel: _visible
              ? l10n.backupEncryptionHidePassword
              : l10n.backupEncryptionShowPassword,
          onTap: () => setState(() => _visible = !_visible),
        ),
      ),
      if (widget.creating) ...[
        const SizedBox(height: 12),
        IosFormTextField(
          key: const ValueKey('backup-password-confirmation'),
          label: l10n.backupEncryptionConfirmPassword,
          controller: _confirmation,
          inlineLabel: false,
          outerPadding: EdgeInsets.zero,
          obscureText: !_visible,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
      ],
      if (widget.retry ||
          (widget.creating &&
              _confirmation.text.isNotEmpty &&
              !_valid)) ...[
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            widget.retry
                ? l10n.backupEncryptionFailed
                : l10n.backupEncryptionMismatch,
            style: TextStyle(fontSize: 13, color: cs.error),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          widget.creating
              ? l10n.backupEncryptionPasswordHint
              : l10n.backupEncryptionUnlockHint,
          style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    ];
    final actions = FormSheetActions(
      key: const ValueKey('backup-password-actions'),
      cancelLabel: MaterialLocalizations.of(context).cancelButtonLabel,
      confirmLabel: widget.creating
          ? MaterialLocalizations.of(context).saveButtonLabel
          : l10n.backupEncryptionUnlock,
      onCancel: () => Navigator.of(context).pop(),
      onConfirm: _valid ? _submit : null,
    );
    if (!ResponsiveHelper.isDesktop(context)) {
      return FormSheet(
        title: widget.creating
            ? l10n.backupEncryptionTitle
            : l10n.backupEncryptionUnlockTitle,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        actions: actions,
        children: children,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDialogHeader(
          title: widget.creating
              ? l10n.backupEncryptionTitle
              : l10n.backupEncryptionUnlockTitle,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
        Padding(padding: const EdgeInsets.all(16), child: actions),
      ],
    );
  }
}
