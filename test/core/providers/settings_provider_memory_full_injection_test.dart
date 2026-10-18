import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/memory_entry.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';

import '../../support/business_test_harness.dart';

/// 全量注入类型：默认空、落盘为类型名列表、重启后恢复、copyWith 保留。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'memory_full_injection_types_v1';

  late BusinessTestHarness harness;

  setUp(() async {
    harness = await createBusinessTestHarness();
  });

  test('默认不含任何类型，也不写入存档', () async {
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;

    expect(settings.memoryFullInjectionTypes, isEmpty);
    expect(await harness.repository.getPreference(key), isNull);
  });

  test('设置后落盘为类型名列表，重新加载能恢复', () async {
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;

    await settings.setMemoryFullInjectionTypes({
      MemoryType.voice,
      MemoryType.instruction,
    });

    expect(settings.memoryFullInjectionTypes, {
      MemoryType.voice,
      MemoryType.instruction,
    });
    final stored = await harness.repository.getPreference(key) as List;
    expect(stored.toSet(), {'voice', 'instruction'});

    final reloaded = SettingsProvider(harness.preferences);
    await reloaded.loaded;
    expect(reloaded.memoryFullInjectionTypes, {
      MemoryType.voice,
      MemoryType.instruction,
    });
  });

  test('清空后落盘为空列表', () async {
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;

    await settings.setMemoryFullInjectionTypes({MemoryType.voice});
    await settings.setMemoryFullInjectionTypes({});

    expect(settings.memoryFullInjectionTypes, isEmpty);
    expect(await harness.repository.getPreference(key), isEmpty);
  });

  test('copyWith 保留该设置', () async {
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;
    await settings.setMemoryFullInjectionTypes({MemoryType.workflow});

    final copy = settings.copyWith();
    expect(copy.memoryFullInjectionTypes, {MemoryType.workflow});
  });
}
