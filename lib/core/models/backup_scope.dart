import '../database/business_data.dart';

/// 备份/恢复时可以选择的数据类别。
///
/// 只有 14 个类别：上游把“环境变量”单独列了一类，本仓库没有独立存储
/// （环境变量存在工作区实体里），所以并进 [workspaces]，不单列。
enum BackupCategory {
  chats,
  files,
  assistants,
  providers,
  mcp,
  skills,
  worldBooks,
  memories,
  quickPhrases,
  instructions,
  workspaces,
  searchServices,
  speechServices,
  settings,
}

/// 一份备份范围：默认全部包含，只记录被排除的类别。
final class BackupScope {
  const BackupScope({this.excluded = const {}});

  /// 旧包的等价范围：旧版本没有类别字段，按“全部包含”理解。
  static const BackupScope all = BackupScope();

  final Set<BackupCategory> excluded;

  bool includes(BackupCategory category) => !excluded.contains(category);

  /// 两个范围的交集：只有两边都包含的类别才算包含。
  BackupScope intersect(BackupScope other) =>
      BackupScope(excluded: Set.unmodifiable({...excluded, ...other.excluded}));

  BackupScope withCategory(BackupCategory category, bool enabled) =>
      BackupScope(
        excluded: Set.unmodifiable({
          ...excluded.where((value) => value != category),
          if (!enabled) category,
        }),
      );

  bool get isEmpty => BackupCategory.values.every((value) => !includes(value));

  Map<String, bool> toJson() => {
    for (final category in BackupCategory.values)
      category.name: includes(category),
  };

  /// 读清单里的范围字段。
  ///
  /// - 字段缺失（旧包）→ 全部包含；
  /// - 不认识的类别名忽略：本仓库没有的类别（例如上游的 environmentVariables）
  ///   本来就不影响我们导出什么；
  /// - 值不是布尔 → 视为清单损坏。
  factory BackupScope.fromJson(Object? value) {
    if (value == null) return BackupScope.all;
    if (value is! Map || value.values.any((enabled) => enabled is! bool)) {
      throw const FormatException('backup_scope');
    }
    return BackupScope(
      excluded: Set.unmodifiable({
        for (final category in BackupCategory.values)
          if (value[category.name] == false) category,
      }),
    );
  }

  /// 该范围要带上的业务实体种类。
  Set<BusinessEntityKind> get entityKinds => {
    if (includes(BackupCategory.assistants)) ...{
      BusinessEntityKind.assistant,
      BusinessEntityKind.assistantGroup,
      BusinessEntityKind.userProfileField,
    },
    if (includes(BackupCategory.providers)) ...{
      BusinessEntityKind.provider,
      BusinessEntityKind.providerGroup,
    },
    if (includes(BackupCategory.mcp)) BusinessEntityKind.mcpServer,
    if (includes(BackupCategory.skills)) BusinessEntityKind.skill,
    if (includes(BackupCategory.worldBooks)) BusinessEntityKind.worldBook,
    if (includes(BackupCategory.memories)) ...{
      BusinessEntityKind.assistantMemory,
      BusinessEntityKind.memoryEntry,
    },
    if (includes(BackupCategory.quickPhrases)) BusinessEntityKind.quickPhrase,
    if (includes(BackupCategory.instructions))
      BusinessEntityKind.instructionInjection,
    if (includes(BackupCategory.workspaces)) BusinessEntityKind.workspace,
    if (includes(BackupCategory.searchServices))
      BusinessEntityKind.searchService,
    if (includes(BackupCategory.speechServices)) BusinessEntityKind.ttsService,
  };

  /// 附件根目录。`sessions` 属于工作区会话记录，跟着 [workspaces] 走。
  Set<String> get assetRoots => {
    if (includes(BackupCategory.files)) ...{
      'upload',
      'images',
      'avatars',
      'fonts',
    },
    if (includes(BackupCategory.workspaces)) 'sessions',
    if (includes(BackupCategory.skills)) 'skills',
    if (includes(BackupCategory.workspaces)) 'workspaces',
  };
}
