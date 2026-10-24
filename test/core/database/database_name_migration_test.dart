import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/database/database_name_migration.dart';
import 'package:Kelivo/core/database/database_names.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('database-name-migration-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> writeFamily(String base, String body) async {
    for (final suffix in DatabaseNames.familySuffixes) {
      if (suffix == '-journal') continue;
      await File(
        p.join(root.path, '$base$suffix'),
      ).writeAsString('$body$suffix');
    }
  }

  test('legacy-only family is renamed with sidecars', () async {
    await writeFamily(DatabaseNames.legacy, 'old');
    final conflict = await DatabaseNameMigration.inspect(root);
    expect(conflict, isNull);
    expect(
      await File(p.join(root.path, DatabaseNames.current)).readAsString(),
      'old',
    );
    expect(
      await File(
        p.join(root.path, '${DatabaseNames.current}-wal'),
      ).readAsString(),
      'old-wal',
    );
    expect(
      await File(p.join(root.path, DatabaseNames.legacy)).exists(),
      isFalse,
    );
  });

  test('both families produce a conflict without opening either', () async {
    await writeFamily(DatabaseNames.current, 'new');
    await writeFamily(DatabaseNames.legacy, 'old');
    final conflict = await DatabaseNameMigration.inspect(root);
    expect(conflict, isNotNull);
    expect(conflict!.currentFiles, hasLength(3));
    expect(conflict.legacyFiles, hasLength(3));
    expect(conflict.quarantineDirectory.path, contains('database-conflicts'));
    expect(
      await File(p.join(root.path, DatabaseNames.current)).readAsString(),
      'new',
    );
    expect(
      await File(p.join(root.path, DatabaseNames.legacy)).readAsString(),
      'old',
    );
  });

  test('choosing current quarantines the legacy family intact', () async {
    await writeFamily(DatabaseNames.current, 'new');
    await writeFamily(DatabaseNames.legacy, 'old');
    final conflict = (await DatabaseNameMigration.inspect(root))!;
    await DatabaseNameMigration.resolve(
      conflict,
      DatabaseConflictChoice.current,
    );
    expect(
      await File(p.join(root.path, DatabaseNames.current)).readAsString(),
      'new',
    );
    expect(
      await File(p.join(root.path, DatabaseNames.legacy)).exists(),
      isFalse,
    );
    final moved = File(
      p.join(conflict.quarantineDirectory.path, DatabaseNames.legacy),
    );
    expect(await moved.readAsString(), 'old');
    expect(
      await File(
        p.join(conflict.quarantineDirectory.path, 'manifest.json'),
      ).exists(),
      isTrue,
    );
  });

  test('choosing legacy quarantines current then renames legacy', () async {
    await writeFamily(DatabaseNames.current, 'new');
    await writeFamily(DatabaseNames.legacy, 'old');
    final conflict = (await DatabaseNameMigration.inspect(root))!;
    await DatabaseNameMigration.resolve(
      conflict,
      DatabaseConflictChoice.legacy,
    );
    expect(
      await File(p.join(root.path, DatabaseNames.current)).readAsString(),
      'old',
    );
    expect(
      await File(p.join(root.path, DatabaseNames.legacy)).exists(),
      isFalse,
    );
    final moved = File(
      p.join(conflict.quarantineDirectory.path, DatabaseNames.current),
    );
    expect(await moved.readAsString(), 'new');
  });

  test('resume moves stray legacy sidecars beside the current main', () async {
    await File(p.join(root.path, DatabaseNames.current)).writeAsString('new');
    await File(
      p.join(root.path, '${DatabaseNames.legacy}-wal'),
    ).writeAsString('wal');
    final conflict = await DatabaseNameMigration.inspect(root);
    expect(conflict, isNull);
    expect(
      await File(
        p.join(root.path, '${DatabaseNames.current}-wal'),
      ).readAsString(),
      'wal',
    );
  });
}
