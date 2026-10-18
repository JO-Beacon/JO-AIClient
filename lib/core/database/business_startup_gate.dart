import 'package:flutter/foundation.dart';

import 'business_migration_engine.dart';
import 'business_preferences.dart';
import 'business_repository.dart';

/// 在公开业务状态之前完成一次性旧版迁移。
///
/// 将该 gate 放在 widget tree 之外，可防止当迁移、验证或旧版清理失败时
/// provider 观察到空的数据库。
final class BusinessStartupGate {
  BusinessStartupGate._();

  /// 当上次 [migrateAndLoad] 发生迁移校验失败时，这里不再降级处理。
  ///
  /// 以前这里会“带默认值进入”，而空的助手列表会让初始化重建一套助手，
  /// 把旧身份和历史顶掉。现在校验类失败也直接抛出，宁可在启动页停下。
  static Future<BusinessPreferences> migrateAndLoad({
    required BusinessRepository repository,
    required LegacyBusinessPreferences legacyPreferences,
    @visibleForTesting Future<void> Function()? debugRunMigration,
  }) async {
    await (debugRunMigration ??
        BusinessMigrationEngine(
          repository: repository,
          legacyPreferences: legacyPreferences,
        ).run)();
    final preferences = BusinessPreferences(repository);
    await preferences.load();
    return preferences;
  }
}
