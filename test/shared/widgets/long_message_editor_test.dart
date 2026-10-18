import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/shared/widgets/long_message_editor.dart';

/// 包装组件的分叉规则：达到 2048 字符、不含从右到左文字与异常换行时才用按行编辑器；
/// `enabled: false`（我们的开关关闭）时始终用原生输入框。
void main() {
  Future<LongMessageEditorState> pump(
    WidgetTester tester,
    String text, {
    bool enabled = true,
  }) async {
    final controller = TextEditingController(text: text);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LongMessageEditor(
            controller: controller,
            enabled: enabled,
            decoration: const InputDecoration(border: InputBorder.none),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<LongMessageEditorState>(find.byType(LongMessageEditor));
  }

  testWidgets('短文本用原生输入框', (tester) async {
    final state = await pump(tester, '短消息');
    expect(state.usesLineEditor, isFalse);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('长文本切成按行编辑器', (tester) async {
    final state = await pump(tester, List.filled(800, '长文本').join());
    expect(state.usesLineEditor, isTrue);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('开关关闭时即使长文本也用原生输入框', (tester) async {
    final state = await pump(
      tester,
      List.filled(800, '长文本').join(),
      enabled: false,
    );
    expect(state.usesLineEditor, isFalse);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('长文本含异常换行时退回原生输入框', (tester) async {
    final state = await pump(tester, '${List.filled(800, '长文本').join()}\r\n');
    expect(state.usesLineEditor, isFalse);
  });

  testWidgets('长文本含从右到左文字时退回原生输入框', (tester) async {
    final state = await pump(tester, '${List.filled(800, '长文本').join()}עברית');
    expect(state.usesLineEditor, isFalse);
  });
}
