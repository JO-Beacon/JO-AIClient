import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/shared/widgets/streaming_rich_text.dart';

/// 分块排版的入口阈值：流式阶段 512 字符、已完成消息 2048；以下直接交给
/// Flutter 整段排版（不再建分块森林、视口观察与约束构建器）。
/// 观测方式：短文本走 `RepaintBoundary(child: Text)`，长文本走 LayoutBuilder。
void main() {
  Future<bool> usesChunkedLayout(
    WidgetTester tester, {
    required int length,
    required bool streaming,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingRichText(
            text: Text(List.filled(length, 'a').join()),
            streaming: streaming,
          ),
        ),
      ),
    );
    return find.byType(LayoutBuilder).evaluate().isNotEmpty;
  }

  testWidgets('短段落直接整段排版', (tester) async {
    expect(
      await usesChunkedLayout(tester, length: 100, streaming: true),
      isFalse,
    );
  });

  testWidgets('流式阶段超过 512 字符开始分块', (tester) async {
    expect(
      await usesChunkedLayout(tester, length: 600, streaming: true),
      isTrue,
    );
  });

  testWidgets('已完成消息在 2048 以内仍整段排版', (tester) async {
    expect(
      await usesChunkedLayout(tester, length: 600, streaming: false),
      isFalse,
    );
  });

  testWidgets('已完成消息超过 2048 才分块', (tester) async {
    expect(
      await usesChunkedLayout(tester, length: 2100, streaming: false),
      isTrue,
    );
  });
}
