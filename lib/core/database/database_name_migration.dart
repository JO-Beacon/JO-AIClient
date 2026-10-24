import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'database_names.dart';

enum DatabaseConflictChoice { current, legacy, exit }

/// Both database families exist. Until the user chooses, neither is opened.
final class DatabaseConflict {
  const DatabaseConflict({
    required this.directory,
    required this.currentFiles,
    required this.legacyFiles,
    required this.quarantineDirectory,
  });

  final Directory directory;
  final List<File> currentFiles;
  final List<File> legacyFiles;
  final Directory quarantineDirectory;

  List<File> get _allFiles => [...currentFiles, ...legacyFiles];

  int get totalBytes => _allFiles.fold(0, (sum, file) {
    try {
      return sum + file.lengthSync();
    } on FileSystemException {
      return sum;
    }
  });
}

/// 把本应用库从旧名 `kelivo.db` 迁到 `jo_aiclient.db`，并在两个家族同时存在
/// 时进入用户选择流程。必须在任何数据库被打开之前调用。
abstract final class DatabaseNameMigration {
  static Future<DatabaseConflict?> inspect(Directory root) async {
    final current = await _family(root, DatabaseNames.current);
    final legacy = await _family(root, DatabaseNames.legacy);
    final currentMain = await _exists(p.join(root.path, DatabaseNames.current));
    final legacyMain = await _exists(p.join(root.path, DatabaseNames.legacy));
    if (currentMain && legacyMain) {
      return DatabaseConflict(
        directory: root,
        currentFiles: current,
        legacyFiles: legacy,
        quarantineDirectory: Directory(
          p.join(root.path, DatabaseNames.conflictDirectory, _stamp()),
        ),
      );
    }
    // 只有主库存在才代表一个可用的数据库；孤立 sidecar 只做归位或隔离。
    if (currentMain) {
      await _adoptOrQuarantineStraySidecars(
        root,
        from: DatabaseNames.legacy,
        to: DatabaseNames.current,
      );
      return null;
    }
    if (legacyMain) {
      await _renameFamily(
        root,
        from: DatabaseNames.legacy,
        to: DatabaseNames.current,
      );
      return null;
    }
    return null;
  }

  static Future<void> resolve(
    DatabaseConflict conflict,
    DatabaseConflictChoice choice,
  ) async {
    switch (choice) {
      case DatabaseConflictChoice.exit:
        return;
      case DatabaseConflictChoice.current:
        await _quarantine(
          conflict,
          conflict.legacyFiles,
          kept: DatabaseNames.current,
        );
      case DatabaseConflictChoice.legacy:
        await _quarantine(
          conflict,
          conflict.currentFiles,
          kept: DatabaseNames.legacy,
        );
        await _renameFamily(
          conflict.directory,
          from: DatabaseNames.legacy,
          to: DatabaseNames.current,
        );
    }
  }

  static Future<List<File>> _family(Directory root, String base) async {
    final files = <File>[];
    for (final suffix in DatabaseNames.familySuffixes) {
      final file = File(p.join(root.path, '$base$suffix'));
      if (await _exists(file.path)) files.add(file);
    }
    return files;
  }

  static Future<bool> _exists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) ==
      FileSystemEntityType.file;

  static Future<void> _adoptOrQuarantineStraySidecars(
    Directory root, {
    required String from,
    required String to,
  }) async {
    final stray = <File>[];
    for (final suffix in DatabaseNames.familySuffixes.skip(1)) {
      final source = File(p.join(root.path, '$from$suffix'));
      if (!await _exists(source.path)) continue;
      final target = File(p.join(root.path, '$to$suffix'));
      if (!await _exists(target.path)) {
        await source.rename(target.path);
      } else {
        stray.add(source);
      }
    }
    if (stray.isEmpty) return;
    final destination = Directory(
      p.join(root.path, DatabaseNames.conflictDirectory, _stamp()),
    );
    await _moveFiles(destination, stray, kept: to);
  }

  static Future<void> _renameFamily(
    Directory root, {
    required String from,
    required String to,
  }) async {
    // 主库先改名：若中途崩溃，下一次启动看到新主库 + 旧 sidecar，
    // 会把 sidecar 归位；反过来则可能让旧主库在没有 WAL 的情况下被打开。
    final main = File(p.join(root.path, from));
    if (!await _exists(main.path)) {
      throw const FileSystemException('database_name_source_missing');
    }
    final targetMain = File(p.join(root.path, to));
    if (await _exists(targetMain.path)) {
      throw const FileSystemException('database_name_target_exists');
    }
    await main.rename(targetMain.path);
    for (final suffix in DatabaseNames.familySuffixes.skip(1)) {
      final source = File(p.join(root.path, '$from$suffix'));
      if (!await _exists(source.path)) continue;
      final target = File(p.join(root.path, '$to$suffix'));
      if (await _exists(target.path)) {
        throw const FileSystemException('database_name_sidecar_conflict');
      }
      await source.rename(target.path);
    }
  }

  static Future<void> _quarantine(
    DatabaseConflict conflict,
    List<File> files, {
    required String kept,
  }) async {
    if (files.isEmpty) return;
    await _moveFiles(conflict.quarantineDirectory, files, kept: kept);
  }

  static Future<void> _moveFiles(
    Directory destination,
    List<File> files, {
    required String kept,
  }) async {
    await destination.create(recursive: true);
    for (final file in files) {
      final target = File(p.join(destination.path, p.basename(file.path)));
      await file.rename(target.path);
    }
    final manifest = File(p.join(destination.path, 'manifest.json'));
    await manifest.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'reason': 'database-name-conflict',
        'kept': kept,
        'files': [for (final file in files) p.basename(file.path)],
        'createdAt': DateTime.now().toIso8601String(),
      }),
      flush: true,
    );
  }

  static String _stamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
