import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'restore_receipt.dart';

const _componentOrder = [RestoreComponent.database, RestoreComponent.assets];
final _runIdPattern = RegExp(r'^[a-f0-9]{32}$');
final _hashPattern = RegExp(r'^[a-f0-9]{64}$');

enum RestorePreviousDatabaseState { missing, file }

enum RestorePreviousAssetRootState { missing, directory }

final class RestoreFileDescriptor {
  const RestoreFileDescriptor({required this.bytes, required this.sha256});

  final int bytes;
  final String sha256;

  Map<String, dynamic> toJson() => {'bytes': bytes, 'sha256': sha256};
}

enum RestoreAssetEntryType { file, link, pipe, socket }

/// 恢复时被改名保存的本机条目。链接是不可打开的：目标只记录、不跟随。
final class RestoreAssetDescriptor {
  const RestoreAssetDescriptor.file(RestoreFileDescriptor descriptor)
    : type = RestoreAssetEntryType.file,
      file = descriptor,
      linkTarget = null;

  const RestoreAssetDescriptor.link(String target)
    : type = RestoreAssetEntryType.link,
      file = null,
      linkTarget = target;

  const RestoreAssetDescriptor.pipe()
    : type = RestoreAssetEntryType.pipe,
      file = null,
      linkTarget = null;

  const RestoreAssetDescriptor.socket()
    : type = RestoreAssetEntryType.socket,
      file = null,
      linkTarget = null;

  final RestoreAssetEntryType type;
  final RestoreFileDescriptor? file;
  final String? linkTarget;

  int get bytes => file?.bytes ?? utf8.encode(linkTarget ?? '').length;

  bool matches(RestoreAssetDescriptor? other) =>
      other != null &&
      type == other.type &&
      file?.bytes == other.file?.bytes &&
      file?.sha256 == other.file?.sha256 &&
      linkTarget == other.linkTarget;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    if (file != null) 'descriptor': file!.toJson(),
    if (linkTarget != null) 'target': linkTarget,
  };

  factory RestoreAssetDescriptor.fromJson(Object? source, String field) {
    final type = source is Map ? source['type'] : null;
    final json = _requireMap(source, switch (type) {
      'file' => const {'type', 'descriptor'},
      'link' => const {'type', 'target'},
      'pipe' || 'socket' => const {'type'},
      _ => throw FormatException('restore_previous_asset_descriptor:$field'),
    }, 'restore_previous_asset_descriptor:$field');
    final descriptor = switch (type) {
      'file' => RestoreAssetDescriptor.file(
        _parseDescriptor(json['descriptor'], field),
      ),
      'link' when json['target'] is String => RestoreAssetDescriptor.link(
        json['target'] as String,
      ),
      'pipe' => const RestoreAssetDescriptor.pipe(),
      'socket' => const RestoreAssetDescriptor.socket(),
      _ => throw FormatException('restore_previous_asset_descriptor:$field'),
    };
    try {
      descriptor._validate(field);
    } catch (_) {
      throw FormatException('restore_previous_asset_descriptor:$field');
    }
    return descriptor;
  }

  void _validate(String field) {
    if (file != null) _validateDescriptor(file!, field);
    if (linkTarget != null &&
        (linkTarget!.isEmpty || linkTarget!.contains('\u0000'))) {
      throw ArgumentError('restore_previous_asset_link:$field');
    }
  }
}

final class RestorePreviousDatabasePlan {
  const RestorePreviousDatabasePlan._({
    required this.state,
    required this.descriptor,
  });

  static const databasePath = 'database/kelivo.db';

  final RestorePreviousDatabaseState state;
  final RestoreFileDescriptor? descriptor;

  factory RestorePreviousDatabasePlan.missing() {
    return const RestorePreviousDatabasePlan._(
      state: RestorePreviousDatabaseState.missing,
      descriptor: null,
    );
  }

  factory RestorePreviousDatabasePlan.file(RestoreFileDescriptor descriptor) {
    _validateDescriptor(descriptor, 'database');
    return RestorePreviousDatabasePlan._(
      state: RestorePreviousDatabaseState.file,
      descriptor: descriptor,
    );
  }

  Map<String, dynamic> toJson() => {
    'state': state.name,
    'path': databasePath,
    'descriptor': descriptor?.toJson(),
  };

  factory RestorePreviousDatabasePlan.fromJson(Object? source) {
    final json = _requireMap(source, const {
      'state',
      'path',
      'descriptor',
    }, 'restore_previous_database');
    if (json['state'] is! String || json['path'] != databasePath) {
      throw const FormatException('restore_previous_database');
    }
    return switch (json['state']) {
      'missing' when json['descriptor'] == null =>
        RestorePreviousDatabasePlan.missing(),
      'file' => RestorePreviousDatabasePlan.file(
        _parseDescriptor(json['descriptor'], 'database'),
      ),
      _ => throw const FormatException('restore_previous_database'),
    };
  }
}

final class RestorePreviousAssetsPlan {
  static const rootNames = [
    'upload',
    'images',
    'avatars',
    'fonts',
    'skills',
    'workspaces',
    'sessions',
  ];

  RestorePreviousAssetsPlan({
    required Map<String, RestorePreviousAssetRootState> rootStates,
    required Map<String, RestoreAssetDescriptor> entries,
  }) : rootStates = Map.unmodifiable({
         for (final root in rootNames)
           if (rootStates.containsKey(root)) root: rootStates[root]!,
       }),
       entries = Map.unmodifiable({
         for (final name in (entries.keys.toList()..sort()))
           name: entries[name]!,
       }) {
    if (rootStates.length != rootNames.length ||
        !rootNames.every(rootStates.containsKey)) {
      throw ArgumentError('restore_previous_asset_roots');
    }
    final foldedNames = <String>{};
    for (final entry in this.entries.entries) {
      final root = _assetRootFor(entry.key);
      if (root == null ||
          this.rootStates[root] != RestorePreviousAssetRootState.directory ||
          !foldedNames.add(entry.key.toLowerCase())) {
        throw ArgumentError('restore_previous_asset_entry:${entry.key}');
      }
      entry.value._validate(entry.key);
    }
  }

  final Map<String, RestorePreviousAssetRootState> rootStates;
  final Map<String, RestoreAssetDescriptor> entries;

  Map<String, dynamic> toJson({
    int formatVersion = RestorePreviousPlan.formatVersion,
  }) => {
    'roots': {for (final root in rootNames) root: rootStates[root]!.name},
    'entries': {
      for (final entry in entries.entries)
        entry.key: formatVersion == 2
            ? entry.value.file!.toJson()
            : entry.value.toJson(),
    },
  };

  factory RestorePreviousAssetsPlan.fromJson(
    Object? source, {
    int formatVersion = RestorePreviousPlan.formatVersion,
  }) {
    final json = _requireMap(source, const {
      'roots',
      'entries',
    }, 'restore_previous_assets');
    final rawRoots = json['roots'];
    final rawEntries = json['entries'];
    if (rawRoots is! Map || rawEntries is! Map) {
      throw const FormatException('restore_previous_assets');
    }
    if (rawRoots.keys.any((key) => key is! String) ||
        rawRoots.length != rootNames.length ||
        !rootNames.every(rawRoots.containsKey)) {
      throw const FormatException('restore_previous_asset_roots');
    }
    final roots = <String, RestorePreviousAssetRootState>{};
    for (final root in rootNames) {
      final rawState = rawRoots[root];
      if (rawState is! String) {
        throw const FormatException('restore_previous_asset_roots');
      }
      roots[root] = RestorePreviousAssetRootState.values.firstWhere(
        (state) => state.name == rawState,
        orElse: () =>
            throw const FormatException('restore_previous_asset_roots'),
      );
    }
    if (rawEntries.keys.any((key) => key is! String)) {
      throw const FormatException('restore_previous_asset_entries');
    }
    final entries = <String, RestoreAssetDescriptor>{};
    for (final entry in rawEntries.entries) {
      entries[entry.key as String] = formatVersion == 2
          ? RestoreAssetDescriptor.file(
              _parseDescriptor(entry.value, entry.key as String),
            )
          : RestoreAssetDescriptor.fromJson(entry.value, entry.key as String);
    }
    try {
      return RestorePreviousAssetsPlan(rootStates: roots, entries: entries);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('restore_previous_assets');
    }
  }
}

final class RestorePreviousPlan {
  RestorePreviousPlan._({
    required this.runId,
    required this.preparedReceiptChecksum,
    required this.candidateManifestSha256,
    required Set<RestoreComponent> selectedComponents,
    required this.createdAtUtc,
    required this.database,
    this.assets,
    int? persistedFormatVersion,
  }) : selectedComponents = Set.unmodifiable(selectedComponents),
       _persistedFormatVersion =
           persistedFormatVersion ?? RestorePreviousPlan.formatVersion {
    if (!_runIdPattern.hasMatch(runId)) {
      throw ArgumentError.value(runId, 'runId');
    }
    _validateHash(preparedReceiptChecksum, 'preparedReceiptChecksum');
    _validateHash(candidateManifestSha256, 'candidateManifestSha256');
    if (!createdAtUtc.isUtc) {
      throw ArgumentError.value(createdAtUtc, 'createdAtUtc');
    }
    if (!this.selectedComponents.contains(RestoreComponent.database) ||
        this.selectedComponents.contains(RestoreComponent.assets) !=
            (assets != null)) {
      throw ArgumentError('restore_previous_components');
    }
  }

  static const format = 'kelivo.restore-previous-plan';
  static const formatVersion = 3;

  final String runId;
  final String preparedReceiptChecksum;
  final String candidateManifestSha256;
  final Set<RestoreComponent> selectedComponents;
  final DateTime createdAtUtc;
  final RestorePreviousDatabasePlan database;
  final RestorePreviousAssetsPlan? assets;

  factory RestorePreviousPlan.forPreparedReceipt({
    required RestoreReceipt receipt,
    required RestorePreviousDatabasePlan database,
    RestorePreviousAssetsPlan? assets,
  }) {
    if (receipt.state != RestoreReceiptState.prepared ||
        receipt.sequence != 1) {
      throw ArgumentError('restore_previous_receipt');
    }
    return RestorePreviousPlan._(
      runId: receipt.runId,
      preparedReceiptChecksum: receipt.checksum,
      candidateManifestSha256: receipt.candidateManifestSha256,
      selectedComponents: receipt.selectedComponents,
      createdAtUtc: receipt.createdAtUtc,
      database: database,
      assets: assets,
    );
  }

  void validatePreparedReceipt(RestoreReceipt receipt) {
    if (receipt.state != RestoreReceiptState.prepared ||
        receipt.sequence != 1 ||
        receipt.runId != runId ||
        receipt.checksum != preparedReceiptChecksum ||
        receipt.candidateManifestSha256 != candidateManifestSha256 ||
        receipt.createdAtUtc != createdAtUtc ||
        !_sameComponents(receipt.selectedComponents, selectedComponents)) {
      throw StateError('restore_previous_receipt');
    }
  }

  /// 这份计划在磁盘上的格式版本。续写时必须沿用，
  /// 因为它的字节哈希被后续回执当作证据。
  final int _persistedFormatVersion;

  String get checksum =>
      sha256.convert(utf8.encode(jsonEncode(_payloadJson()))).toString();

  Map<String, dynamic> toJson({int? formatVersion}) {
    final payload = _payloadJson(formatVersion: formatVersion);
    final sum = sha256.convert(utf8.encode(jsonEncode(payload))).toString();
    return {...payload, 'checksum': sum};
  }

  Map<String, dynamic> _payloadJson({int? formatVersion}) {
    final version = formatVersion ?? _persistedFormatVersion;
    return {
      'format': format,
      'formatVersion': version,
      'runId': runId,
      'preparedReceiptChecksum': preparedReceiptChecksum,
      'candidateManifestSha256': candidateManifestSha256,
      'selectedComponents': [
        for (final component in _componentOrder)
          if (selectedComponents.contains(component)) component.name,
      ],
      'createdAtUtc': createdAtUtc.toIso8601String(),
      'database': database.toJson(),
      'assets': assets?.toJson(formatVersion: version),
    };
  }

  factory RestorePreviousPlan.fromJson(
    Map<dynamic, dynamic> source, {
    required RestoreReceipt preparedReceipt,
  }) {
    final json = _requireMap(source, const {
      'format',
      'formatVersion',
      'runId',
      'preparedReceiptChecksum',
      'candidateManifestSha256',
      'selectedComponents',
      'createdAtUtc',
      'database',
      'assets',
      'checksum',
    }, 'restore_previous_plan');
    final version = json['formatVersion'];
    if (json['format'] != format ||
        version is! int ||
        (version != 2 && version != formatVersion) ||
        json['runId'] is! String ||
        json['preparedReceiptChecksum'] is! String ||
        json['candidateManifestSha256'] is! String ||
        json['createdAtUtc'] is! String ||
        json['checksum'] is! String) {
      throw const FormatException('restore_previous_plan');
    }
    try {
      final selectedComponents = _parseComponents(json['selectedComponents']);
      final createdAtUtc = DateTime.parse(json['createdAtUtc'] as String);
      if (!createdAtUtc.isUtc ||
          createdAtUtc.toIso8601String() != json['createdAtUtc']) {
        throw const FormatException('restore_previous_created_at');
      }
      final plan = RestorePreviousPlan._(
        runId: json['runId'] as String,
        preparedReceiptChecksum: json['preparedReceiptChecksum'] as String,
        candidateManifestSha256: json['candidateManifestSha256'] as String,
        selectedComponents: selectedComponents,
        createdAtUtc: createdAtUtc,
        database: RestorePreviousDatabasePlan.fromJson(json['database']),
        assets: json['assets'] == null
            ? null
            : RestorePreviousAssetsPlan.fromJson(
                json['assets'],
                formatVersion: version,
              ),
        persistedFormatVersion: version,
      );
      if (!_hashPattern.hasMatch(json['checksum'] as String) ||
          plan.checksum != json['checksum']) {
        throw const FormatException('restore_previous_checksum');
      }
      plan.validatePreparedReceipt(preparedReceipt);
      return plan;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('restore_previous_plan');
    }
  }
}

Map<String, dynamic> _requireMap(
  Object? source,
  Set<String> expectedKeys,
  String error,
) {
  if (source is! Map ||
      source.keys.any((key) => key is! String) ||
      source.length != expectedKeys.length ||
      !source.keys.toSet().containsAll(expectedKeys)) {
    throw FormatException(error);
  }
  return source.cast<String, dynamic>();
}

RestoreFileDescriptor _parseDescriptor(Object? source, String field) {
  final json = _requireMap(source, const {
    'bytes',
    'sha256',
  }, 'restore_previous_descriptor:$field');
  if (json['bytes'] is! int || json['sha256'] is! String) {
    throw FormatException('restore_previous_descriptor:$field');
  }
  final descriptor = RestoreFileDescriptor(
    bytes: json['bytes'] as int,
    sha256: json['sha256'] as String,
  );
  try {
    _validateDescriptor(descriptor, field);
  } catch (_) {
    throw FormatException('restore_previous_descriptor:$field');
  }
  return descriptor;
}

void _validateDescriptor(RestoreFileDescriptor descriptor, String field) {
  if (descriptor.bytes < 0 || !_hashPattern.hasMatch(descriptor.sha256)) {
    throw ArgumentError('restore_previous_descriptor:$field');
  }
}

void _validateHash(String value, String field) {
  if (!_hashPattern.hasMatch(value)) {
    throw ArgumentError.value(value, field);
  }
}

Set<RestoreComponent> _parseComponents(Object? source) {
  if (source is! List || source.any((value) => value is! String)) {
    throw const FormatException('restore_previous_components');
  }
  final raw = source.cast<String>();
  final expected = <String>[];
  final components = <RestoreComponent>{};
  for (final component in _componentOrder) {
    if (raw.contains(component.name)) {
      expected.add(component.name);
      components.add(component);
    }
  }
  if (raw.length != expected.length) {
    throw const FormatException('restore_previous_components');
  }
  for (var index = 0; index < raw.length; index++) {
    if (raw[index] != expected[index]) {
      throw const FormatException('restore_previous_components');
    }
  }
  return components;
}

String? _assetRootFor(String entryName) {
  if (entryName.contains('\\') ||
      p.posix.isAbsolute(entryName) ||
      p.posix.normalize(entryName) != entryName) {
    return null;
  }
  final segments = p.posix.split(entryName);
  if (segments.length < 2 || segments.any((segment) => segment.isEmpty)) {
    return null;
  }
  final root = segments.first;
  return RestorePreviousAssetsPlan.rootNames.contains(root) ? root : null;
}

bool _sameComponents(Set<RestoreComponent> left, Set<RestoreComponent> right) =>
    left.length == right.length && left.containsAll(right);
