import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/database/business_data.dart';
import 'package:Kelivo/core/models/backup_scope.dart';

void main() {
  test('默认包含全部类别', () {
    const scope = BackupScope.all;
    for (final category in BackupCategory.values) {
      expect(scope.includes(category), isTrue, reason: category.name);
    }
    expect(scope.isEmpty, isFalse);
  });

  test('关掉一类后序列化，再读回来保持', () {
    final scope = const BackupScope()
        .withCategory(BackupCategory.providers, false)
        .withCategory(BackupCategory.files, false);
    final json = scope.toJson();
    expect(json['providers'], isFalse);
    expect(json['files'], isFalse);
    expect(json['chats'], isTrue);

    final restored = BackupScope.fromJson(json);
    expect(restored.includes(BackupCategory.providers), isFalse);
    expect(restored.includes(BackupCategory.files), isFalse);
    expect(restored.includes(BackupCategory.settings), isTrue);
  });

  test('旧包没有范围字段时按全选解释', () {
    expect(BackupScope.fromJson(null).isEmpty, isFalse);
    for (final category in BackupCategory.values) {
      expect(BackupScope.fromJson(null).includes(category), isTrue);
    }
  });

  test('不认识的类别名被忽略', () {
    final scope = BackupScope.fromJson({
      'providers': false,
      'environmentVariables': false,
    });
    expect(scope.includes(BackupCategory.providers), isFalse);
    expect(scope.includes(BackupCategory.chats), isTrue);
  });

  test('值不是布尔时视为清单损坏', () {
    expect(
      () => BackupScope.fromJson({'chats': 'yes'}),
      throwsA(isA<FormatException>()),
    );
  });

  test('交集只保留两边都包含的类别', () {
    const left = BackupScope(excluded: {BackupCategory.providers});
    const right = BackupScope(excluded: {BackupCategory.files});
    final both = left.intersect(right);
    expect(both.includes(BackupCategory.providers), isFalse);
    expect(both.includes(BackupCategory.files), isFalse);
    expect(both.includes(BackupCategory.chats), isTrue);
  });

  test('实体类别按映射取舍', () {
    const scope = BackupScope(
      excluded: {
        BackupCategory.providers,
        BackupCategory.memories,
        BackupCategory.quickPhrases,
      },
    );
    final kinds = scope.entityKinds;
    expect(kinds, contains(BusinessEntityKind.assistant));
    expect(kinds, contains(BusinessEntityKind.assistantGroup));
    expect(kinds, contains(BusinessEntityKind.userProfileField));
    expect(kinds, isNot(contains(BusinessEntityKind.provider)));
    expect(kinds, isNot(contains(BusinessEntityKind.providerGroup)));
    expect(kinds, isNot(contains(BusinessEntityKind.assistantMemory)));
    expect(kinds, isNot(contains(BusinessEntityKind.memoryEntry)));
    expect(kinds, isNot(contains(BusinessEntityKind.quickPhrase)));
    expect(kinds, contains(BusinessEntityKind.worldBook));
  });

  test('附件根目录跟着类别走，sessions 归工作区', () {
    const noFiles = BackupScope(excluded: {BackupCategory.files});
    expect(noFiles.assetRoots, isNot(contains('upload')));
    expect(noFiles.assetRoots, isNot(contains('fonts')));
    expect(noFiles.assetRoots, contains('sessions'));
    expect(noFiles.assetRoots, contains('workspaces'));

    const noWorkspaces = BackupScope(excluded: {BackupCategory.workspaces});
    expect(noWorkspaces.assetRoots, contains('upload'));
    expect(noWorkspaces.assetRoots, isNot(contains('sessions')));
    expect(noWorkspaces.assetRoots, isNot(contains('workspaces')));
    expect(noWorkspaces.assetRoots, contains('skills'));

    const noSkills = BackupScope(excluded: {BackupCategory.skills});
    expect(noSkills.assetRoots, isNot(contains('skills')));
  });
}
