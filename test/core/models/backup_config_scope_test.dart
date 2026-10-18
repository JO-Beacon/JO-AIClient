import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/backup.dart';
import 'package:Kelivo/core/models/backup_scope.dart';

/// 备份范围跟着备份目标配置走：序列化往返、旧配置兼容。
void main() {
  test('WebDAV 配置保存并取回范围', () {
    final config = const WebDavConfig().copyWith(
      scope: const BackupScope(
        excluded: {BackupCategory.providers, BackupCategory.memories},
      ),
    );
    final roundTrip = WebDavConfig.fromJson(
      Map<String, dynamic>.from(config.toJson()),
    );
    expect(roundTrip.scope.includes(BackupCategory.providers), isFalse);
    expect(roundTrip.scope.includes(BackupCategory.memories), isFalse);
    expect(roundTrip.scope.includes(BackupCategory.chats), isTrue);
    // 兼容字段与范围保持一致。
    expect(roundTrip.includeChats, isTrue);
    expect(roundTrip.includeFiles, isTrue);
  });

  test('旧配置没有范围字段时由两个布尔还原', () {
    final config = WebDavConfig.fromJson({
      'url': 'https://example.com',
      'includeChats': false,
      'includeFiles': true,
    });
    expect(config.scope.includes(BackupCategory.chats), isFalse);
    expect(config.scope.includes(BackupCategory.files), isTrue);
    // 其他类别默认包含。
    expect(config.scope.includes(BackupCategory.providers), isTrue);
  });

  test('关掉范围后在旧布尔里也体现出来', () {
    final config = const WebDavConfig().copyWith(includeChats: false);
    expect(config.includeChats, isFalse);
    expect(config.toJson()['includeChats'], isFalse);
    expect(config.scope.includes(BackupCategory.chats), isFalse);
  });

  test('S3 配置同样保存范围', () {
    final config = const S3Config().copyWith(
      scope: const BackupScope(excluded: {BackupCategory.files}),
    );
    final roundTrip = S3Config.fromJson(
      Map<String, dynamic>.from(config.toJson()),
    );
    expect(roundTrip.includeFiles, isFalse);
    expect(roundTrip.scope.includes(BackupCategory.files), isFalse);
    expect(roundTrip.scope.includes(BackupCategory.chats), isTrue);
  });
}
