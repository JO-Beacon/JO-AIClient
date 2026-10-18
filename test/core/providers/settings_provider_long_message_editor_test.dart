import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';

import '../../support/business_test_harness.dart';

/// 长文本编辑器开关：默认关、改动落盘、重启后仍是用户选的值。
/// 它是本机键，直写 SharedPreferences（BusinessPreferences 拒绝写 localOnly），
/// 分类断言见 business_migration_engine_test。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'display_long_message_editor_v1';

  late BusinessTestHarness harness;

  setUp(() async {
    harness = await createBusinessTestHarness();
  });

  test('默认关闭，且加载时不写入存档', () async {
    final settings = SettingsProvider(harness.preferences);

    await settings.loaded;

    expect(settings.useLongMessageEditor, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(key), isNull);
  });

  test('打开后落盘，重新加载仍是打开', () async {
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;

    await settings.setUseLongMessageEditor(true);

    expect(settings.useLongMessageEditor, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(key), isTrue);

    final reloaded = SettingsProvider(harness.preferences);
    await reloaded.loaded;
    expect(reloaded.useLongMessageEditor, isTrue);
  });

  test('关掉后落盘为 false，而不是删键', () async {
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;

    await settings.setUseLongMessageEditor(true);
    await settings.setUseLongMessageEditor(false);

    expect(settings.useLongMessageEditor, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(key), isFalse);
  });

  test('重复设置同一个值不会重复通知', () async {
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;

    var notifications = 0;
    settings.addListener(() => notifications++);

    await settings.setUseLongMessageEditor(false);
    expect(notifications, 0);

    await settings.setUseLongMessageEditor(true);
    await settings.setUseLongMessageEditor(true);
    expect(notifications, 1);
  });
}
