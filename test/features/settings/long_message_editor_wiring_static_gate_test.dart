import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 长文本按行编辑器是本仓库独立加的能力，上游没有这个开关。
/// 基线升级时很容易在整文件替换中把这些接线丢掉，而界面不会报错。
/// 这个门禁逐处确认：每个目标字段仍然接入了长文本编辑器，且开关仍被读取。
void main() {
  // 直接使用 LongMessageEditor 的字段必须自己读取开关。
  const directWiring = <String, List<String>>{
    'lib/features/home/widgets/chat_input_bar.dart': ['LongMessageEditor('],
    'lib/features/chat/widgets/message_parts_editor.dart': [
      'LongMessageEditor(',
    ],
    'lib/features/assistant/pages/assistant_settings_edit_prompt_tab.dart': [
      'LongMessageEditor(',
      'useLongMessageEditor',
    ],
    'lib/features/world_book/pages/world_book_page.dart': [
      'LongMessageEditor(',
      'useLongMessageEditor',
    ],
    'lib/features/instruction_injection/pages/instruction_injection_page.dart':
        ['LongMessageEditor(', 'useLongMessageEditor'],
    'lib/features/home/widgets/conversation_system_prompt_editor.dart': [
      'LongMessageEditor(',
      'useLongMessageEditor',
    ],
    'lib/features/settings/widgets/memory_ui.dart': [
      'LongMessageEditor(',
      'useLongMessageEditor',
    ],
    'lib/features/scheduled_tasks/pages/scheduled_task_editor_page.dart': [
      'LongMessageEditor(',
      'useLongMessageEditor',
    ],
    'lib/features/settings/pages/user_profile_page.dart': [
      'LongMessageEditor(',
      'useLongMessageEditor',
    ],
  };

  // 通过共享包装接入的字段：包装内部统一读取开关。
  const wrappedWiring = <String>[
    'lib/features/quick_phrase/pages/quick_phrases_page.dart',
    'lib/desktop/setting/world_book_pane.dart',
    'lib/desktop/setting/instruction_injection_pane.dart',
    'lib/desktop/setting/quick_phrases_pane.dart',
    'lib/features/assistant/pages/assistant_settings_edit_memory_tab_legacy.dart',
    'lib/features/settings/pages/memory_settings_page.dart',
    'lib/features/home/widgets/learning_prompt_sheet.dart',
    'lib/features/model/widgets/ocr_prompt_sheet.dart',
    'lib/features/translate/pages/translate_page.dart',
    'lib/desktop/desktop_translate_page.dart',
  ];

  test('长文本编辑器的接入点没有被基线合并或重构悄悄删掉', () async {
    final offenders = <String>[];
    for (final entry in directWiring.entries) {
      final content = await File(entry.key).readAsString();
      for (final marker in entry.value) {
        if (!content.contains(marker)) {
          offenders.add('${entry.key} 缺少 $marker');
        }
      }
    }
    for (final path in wrappedWiring) {
      final content = await File(path).readAsString();
      if (!content.contains('LongTextField(')) {
        offenders.add('$path 缺少 LongTextField(');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '这些接线是本仓库独立添加的，基线升级时必须逐处保留；'
          '若字段确实被移除，请同步更新本测试的清单。',
    );
  });
}
