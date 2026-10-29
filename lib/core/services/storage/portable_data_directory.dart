import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app_build_identity.dart';
import '../../database/app_database.dart';
import '../../database/database_names.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/app_directories.dart';
import '../backup/restore_business_lease.dart';
import '../backup/restore_startup_gate.dart';
import 'data_directory_paths.dart';
import 'windows_data_directory.dart';

/// Prepares the program-local `data` directory for a portable Windows build.
///
/// A portable build never falls back to the installed AppData directory. If no
/// portable data exists, the user may copy installed data into the new root;
/// the source remains untouched.
Future<bool> ensurePortableDataDirectory() async {
  if (!kIsPortableBuild || !Platform.isWindows) return true;
  try {
    return await _ensurePortableDataDirectory();
  } catch (error) {
    final done = Completer<void>();
    runApp(
      _PortableStartupErrorApp(
        error: error,
        onExit: () {
          if (!done.isCompleted) done.complete();
        },
      ),
    );
    await done.future;
    return false;
  }
}

Future<bool> _ensurePortableDataDirectory() async {
  final target = AppDirectories.getPortableDataDirectory();
  if (await target.exists()) {
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('portable_data_target_not_directory');
    }
    return true;
  }

  final support = await getApplicationSupportDirectory();
  final supportPath = await support.resolveSymbolicLinks();
  final locator = WindowsDataDirectory(
    supportDirectory: Directory(supportPath),
  );
  final WindowsDataDirectoryState state;
  try {
    state = await locator.state;
  } on FormatException {
    throw StateError('portable_data_invalid_locator');
  }

  if (state.pending != null) {
    throw StateError('portable_data_pending_move');
  }

  final active = state.active;
  final source = Directory(active?.path ?? supportPath);
  if (active != null) {
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('portable_data_source_unavailable');
    }
    await _verifySourceIdentity(active);
  }

  if (await RestoreStartupGate.hasPendingWork(appDataDirectory: source)) {
    throw StateError('portable_data_pending_restore');
  }

  if (!await _hasInstalledData(source)) {
    await target.create(recursive: true);
    return true;
  }

  final decision = Completer<bool>();
  runApp(
    _PortableMigrationApp(
      source: source,
      target: target,
      onDone: (value) {
        if (!decision.isCompleted) decision.complete(value);
      },
    ),
  );
  return decision.future;
}

Future<void> _verifySourceIdentity(DataDirectoryLocation active) async {
  final marker = File(p.join(active.path, WindowsDataDirectory.identityName));
  if (!await marker.exists()) {
    throw StateError('portable_data_source_identity');
  }
  final decoded = jsonDecode(await marker.readAsString());
  if (decoded is! Map || decoded['id'] != active.id) {
    throw StateError('portable_data_source_identity');
  }
}

Future<bool> _hasInstalledData(Directory directory) async {
  for (final name in [
    AppDatabase.databaseFileName,
    DatabaseNames.legacy,
    'conversations.hive',
    'messages.hive',
  ]) {
    if (await File(p.join(directory.path, name)).exists()) return true;
  }
  return false;
}

class _PortableMigrationApp extends StatefulWidget {
  const _PortableMigrationApp({
    required this.source,
    required this.target,
    required this.onDone,
  });

  final Directory source;
  final Directory target;
  final ValueChanged<bool> onDone;

  @override
  State<_PortableMigrationApp> createState() => _PortableMigrationAppState();
}

class _PortableMigrationAppState extends State<_PortableMigrationApp> {
  bool _busy = false;
  String? _error;

  Future<void> _migrate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _copyInstalledData(widget.source, widget.target);
      if (mounted) widget.onDone(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _migrationErrorMessage(AppLocalizations.of(context)!, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _busy
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(l10n.portableDataMigrationBusy),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.portableDataMigrationTitle,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(l10n.portableDataMigrationMessage),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _migrate,
                          child: Text(l10n.portableDataMigrationCopy),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => widget.onDone(false),
                          child: Text(l10n.portableDataMigrationExit),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PortableStartupErrorApp extends StatelessWidget {
  const _PortableStartupErrorApp({required this.error, required this.onExit});

  final Object error;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.portableDataMigrationTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(_migrationErrorMessage(l10n, error)),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: onExit,
                    child: Text(l10n.portableDataMigrationExit),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _copyInstalledData(Directory source, Directory target) async {
  final sourcePath = p.normalize(source.absolute.path);
  final targetPath = p.normalize(target.absolute.path);
  if (p.equals(sourcePath, targetPath) ||
      p.isWithin(sourcePath, targetPath) ||
      p.isWithin(targetPath, sourcePath)) {
    throw StateError('portable_data_directory_overlap');
  }

  final RestoreBusinessLease lease;
  try {
    lease = await RestoreBusinessLease.acquire(appDataDirectory: source);
  } on RestoreBusinessLeaseUnavailable {
    throw StateError('portable_data_source_busy');
  }

  final staging = Directory('$targetPath.migrating');
  try {
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);

    final before = await _snapshot(source);
    await _copyTree(source, staging);
    final after = await _snapshot(source);
    if (before.length != after.length ||
        before.entries.any((entry) => after[entry.key] != entry.value)) {
      throw StateError('portable_data_source_changed');
    }

    final hasDatabase =
        await File(
          p.join(staging.path, AppDatabase.databaseFileName),
        ).exists() ||
        await File(p.join(staging.path, DatabaseNames.legacy)).exists();
    if (hasDatabase) {
      await DataDirectoryPaths(sourcePath, targetPath).rewriteCopy(staging);
    }
    if (await target.exists()) {
      throw StateError('portable_data_directory_exists');
    }
    await staging.rename(targetPath);
  } catch (_) {
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
    } catch (_) {}
    rethrow;
  } finally {
    await lease.close();
  }
}

Future<Map<String, String>> _snapshot(Directory source) async {
  final result = <String, String>{};
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: source.path);
    if (_isLeasePath(relative) || entity is Link) continue;
    if (entity is File) {
      final stat = await entity.stat();
      result[relative] = '${stat.size}:${stat.modified.microsecondsSinceEpoch}';
    }
  }
  return result;
}

bool _isLeasePath(String relative) =>
    p.split(relative).first == RestoreBusinessLease.leaseDirectoryName;

Future<void> _copyTree(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final name = p.basename(entity.path);
    if (name == RestoreBusinessLease.leaseDirectoryName) continue;
    final destination = p.join(target.path, name);
    if (entity is Directory) {
      await _copyTree(entity, Directory(destination));
    } else if (entity is File) {
      await entity.copy(destination);
    }
  }
}

String _migrationErrorMessage(AppLocalizations l10n, Object error) {
  final code = error is StateError ? error.message : '';
  return switch (code) {
    'portable_data_pending_move' => l10n.portableDataDirectoryPendingMove,
    'portable_data_source_unavailable' => l10n.portableDataDirectoryUnavailable,
    'portable_data_source_identity' => l10n.portableDataDirectoryInvalid,
    'portable_data_source_busy' => l10n.portableDataDirectoryBusy,
    'portable_data_source_changed' => l10n.portableDataDirectoryChanged,
    'portable_data_pending_restore' => l10n.portableDataDirectoryPendingRestore,
    'portable_data_invalid_locator' => l10n.portableDataDirectoryInvalid,
    _ => l10n.portableDataMigrationFailed(error.toString()),
  };
}
