import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/database/business_settings_router.dart';

import '../../support/business_test_harness.dart';

/// 分层表单瓦片：本仓库默认开（保留一直以来的观感），改动落盘、重启后仍是用户选的值。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'display_use_layered_sheet_tiles_v1';

  late BusinessTestHarness harness;

  setUp(() async {
    harness = await createBusinessTestHarness();
  });

  test('默认打开，且加载时不写入存档', () async {
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;

    expect(settings.useLayeredSheetTiles, isTrue);
    expect(await harness.repository.getPreference(key), isNull);
  });

  test('关掉后落盘，重新加载仍是关闭', () async {
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;

    await settings.setUseLayeredSheetTiles(false);

    expect(settings.useLayeredSheetTiles, isFalse);
    expect(await harness.repository.getPreference(key), isFalse);

    final reloaded = SettingsProvider(harness.preferences);
    await reloaded.loaded;
    expect(reloaded.useLayeredSheetTiles, isFalse);
  });

  test('重复设置同一个值不会重复通知', () async {
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;

    var notifications = 0;
    settings.addListener(() => notifications++);

    await settings.setUseLayeredSheetTiles(true);
    expect(notifications, 0);

    await settings.setUseLayeredSheetTiles(false);
    await settings.setUseLayeredSheetTiles(false);
    expect(notifications, 1);
  });

  test('键按展示类业务偏好分类，随备份流转', () {
    expect(
      BusinessKeyRegistry.classify(key),
      BusinessKeyDisposition.preference,
    );
  });
}
