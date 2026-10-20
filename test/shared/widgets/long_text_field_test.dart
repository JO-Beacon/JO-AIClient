import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/shared/widgets/long_text_field.dart';

import '../../support/business_test_harness.dart';

Future<void> _pumpField(
  WidgetTester tester, {
  required TextEditingController controller,
  required bool enabled,
  FocusNode? focusNode,
}) async {
  final settings = SettingsProvider(createBusinessTestPreferences());
  addTearDown(settings.dispose);
  await settings.setUseLongMessageEditor(enabled);
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: MaterialApp(
        home: Scaffold(
          body: LongTextField(
            controller: controller,
            focusNode: focusNode,
            maxLines: 10,
            decoration: const InputDecoration(border: InputBorder.none),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('开关关闭时，长文本仍使用原生输入框', (tester) async {
    final controller = TextEditingController(
      text: List.filled(2200, 'A').join(),
    );
    addTearDown(controller.dispose);

    await _pumpField(tester, controller: controller, enabled: false);

    expect(find.byType(CodeEditor), findsNothing);
    expect(find.byIcon(Lucide.Type), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('开关打开但文本短时，仍使用原生输入框', (tester) async {
    final controller = TextEditingController(text: 'short');
    addTearDown(controller.dispose);

    await _pumpField(tester, controller: controller, enabled: true);

    expect(find.byType(CodeEditor), findsNothing);
    expect(find.byIcon(Lucide.Type), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('开关打开且文本超过阈值时，切换为按行编辑器', (tester) async {
    final controller = TextEditingController(
      text: List.filled(2200, 'A').join(),
    );
    addTearDown(controller.dispose);

    await _pumpField(tester, controller: controller, enabled: true);

    expect(find.byType(CodeEditor), findsOneWidget);
    // 常驻标记随着按行编辑器一起出现。
    expect(find.byIcon(Lucide.Type), findsOneWidget);
  });

  testWidgets('输入中跨过阈值立即切换，但焦点和光标不丢', (tester) async {
    final controller = TextEditingController(
      text: List.filled(2047, 'A').join(),
    );
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await _pumpField(
      tester,
      controller: controller,
      enabled: true,
      focusNode: focusNode,
    );
    focusNode.requestFocus();
    await tester.pump();
    expect(find.byType(CodeEditor), findsNothing);

    final focusStates = <bool>[];
    focusNode.addListener(() => focusStates.add(focusNode.hasFocus));

    controller.value = TextEditingValue(
      text: List.filled(2048, 'A').join(),
      selection: const TextSelection.collapsed(offset: 2048),
    );
    await tester.pumpAndSettle();

    expect(focusStates, everyElement(isTrue), reason: '切换过程中不能出现失焦状态');

    expect(focusNode.hasFocus, isTrue, reason: '跨过阈值不能让输入框失焦');
    expect(controller.selection.baseOffset, 2048, reason: '光标必须留在原位置');
    final lineEditor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    expect(
      lineEditor.controller?.selection.extentOffset,
      2048,
      reason: '按行编辑器的光标也必须留在原位置',
    );
    expect(find.byType(CodeEditor), findsOneWidget, reason: '跨过阈值必须立即切换为按行编辑器');
  });

  testWidgets('输入中删回阈值以下立即切换，但焦点和光标不丢', (tester) async {
    final controller = TextEditingController(
      text: List.filled(2049, 'A').join(),
    );
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await _pumpField(
      tester,
      controller: controller,
      enabled: true,
      focusNode: focusNode,
    );
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(find.byType(CodeEditor), findsOneWidget);

    controller.value = TextEditingValue(
      text: List.filled(2047, 'A').join(),
      selection: const TextSelection.collapsed(offset: 2047),
    );
    await tester.pumpAndSettle();

    expect(focusNode.hasFocus, isTrue, reason: '删回阈值以下不能让输入框失焦');
    expect(controller.selection.baseOffset, 2047, reason: '光标必须留在原位置');
    final nativeEditor = tester.widget<TextField>(find.byType(TextField));
    expect(
      nativeEditor.controller!.selection.baseOffset,
      2047,
      reason: '原生输入框的光标也必须留在原位置',
    );
    expect(find.byType(CodeEditor), findsNothing, reason: '删回阈值以下必须立即换回原生输入框');
  });

  testWidgets('跨过阈值时若系统先收走焦点，切换后要恢复焦点和光标', (tester) async {
    final controller = TextEditingController(
      text: List.filled(2047, 'A').join(),
    );
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await _pumpField(
      tester,
      controller: controller,
      enabled: true,
      focusNode: focusNode,
    );
    focusNode.requestFocus();
    await tester.pump();

    controller.value = TextEditingValue(
      text: List.filled(2048, 'A').join(),
      selection: const TextSelection.collapsed(offset: 2048),
    );
    // 模拟系统在重建输入连接时先把焦点收走。
    focusNode.unfocus();
    await tester.pumpAndSettle();

    expect(find.byType(CodeEditor), findsOneWidget);
    expect(focusNode.hasFocus, isTrue, reason: '切换后必须恢复焦点');
    expect(
      tester
          .widget<CodeEditor>(find.byType(CodeEditor))
          .controller
          ?.selection
          .extentOffset,
      2048,
      reason: '切换后必须恢复光标',
    );
  });

  testWidgets('删回阈值以下时若系统先收走焦点，切换后要恢复焦点和光标', (tester) async {
    final controller = TextEditingController(
      text: List.filled(2049, 'A').join(),
    );
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await _pumpField(
      tester,
      controller: controller,
      enabled: true,
      focusNode: focusNode,
    );
    focusNode.requestFocus();
    await tester.pumpAndSettle();

    controller.value = TextEditingValue(
      text: List.filled(2047, 'A').join(),
      selection: const TextSelection.collapsed(offset: 2047),
    );
    focusNode.unfocus();
    await tester.pumpAndSettle();

    expect(find.byType(CodeEditor), findsNothing);
    expect(focusNode.hasFocus, isTrue, reason: '切换后必须恢复焦点');
    expect(controller.selection.baseOffset, 2047, reason: '切换后必须恢复光标');
  });

  testWidgets('删回阈值以下后要重新接上文字输入，能继续打字', (tester) async {
    final controller = TextEditingController(
      text: List.filled(2049, 'A').join(),
    );
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await _pumpField(
      tester,
      controller: controller,
      enabled: true,
      focusNode: focusNode,
    );
    focusNode.requestFocus();
    await tester.pumpAndSettle();

    tester.testTextInput.log.clear();
    controller.value = TextEditingValue(
      text: List.filled(2000, 'A').join(),
      selection: const TextSelection.collapsed(offset: 2000),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CodeEditor), findsNothing);
    expect(
      tester.testTextInput.hasAnyClients,
      isTrue,
      reason: '切回原生输入框后必须重新建立输入连接，否则只能删不能打',
    );
    expect(
      tester.testTextInput.log.map((call) => call.method),
      contains('TextInput.setClient'),
      reason: '新输入框必须重新注册文字输入客户端',
    );

    final nativeScrollable = find.descendant(
      of: find.byType(TextField),
      matching: find.byType(Scrollable),
    );
    expect(nativeScrollable, findsOneWidget);
    expect(
      tester.state<ScrollableState>(nativeScrollable).position.pixels,
      greaterThan(0),
      reason: '切回普通框后视口应停在光标附近，而不是重置到顶层',
    );
    final caret = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    expect(caret.cursorColor?.a ?? 0, greaterThan(0), reason: '切回普通框后光标必须可见');

    final typed = "${List.filled(2000, 'A').join()}B";
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: typed,
        selection: const TextSelection.collapsed(offset: 2001),
      ),
    );
    await tester.pump();
    expect(controller.text.endsWith('B'), isTrue);
  });

  testWidgets('输入法组合中的文字不能触发 2048 切换', (tester) async {
    final controller = TextEditingController(
      text: List.filled(2000, 'A').join(),
    );
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await _pumpField(
      tester,
      controller: controller,
      enabled: true,
      focusNode: focusNode,
    );
    focusNode.requestFocus();
    await tester.pump();

    // 组合中的拼音等中间产物把总长度推过 2048。
    final composingText = List.filled(2060, 'A').join();
    controller.value = TextEditingValue(
      text: composingText,
      selection: const TextSelection.collapsed(offset: 2060),
      composing: const TextRange(start: 2000, end: 2060),
    );
    await tester.pumpAndSettle();

    expect(
      find.byType(CodeEditor),
      findsNothing,
      reason: '组合期间不能切换编辑器，否则输入法会被打断',
    );
    expect(focusNode.hasFocus, isTrue);

    // 组合上屏，最终文本仍超过阈值，这时才切换。
    controller.value = TextEditingValue(
      text: composingText,
      selection: const TextSelection.collapsed(offset: 2060),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CodeEditor), findsOneWidget);
  });
}
