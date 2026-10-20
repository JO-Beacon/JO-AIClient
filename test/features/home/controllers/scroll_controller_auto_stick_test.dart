import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/home/controllers/scroll_controller.dart'
    as scroll_ctrl;

void main() {
  testWidgets('内容变高、用户没有向上滚动时，不得清掉自动跟随', (tester) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final chatScroll = scroll_ctrl.ChatScrollController(
      scrollController: scrollController,
      onStateChanged: () {},
      getAutoScrollEnabled: () => true,
      getAutoScrollIdleSeconds: () => 3,
      getTopRevealInset: () => 0,
      isGenerating: () => false,
    );
    addTearDown(chatScroll.dispose);

    final count = ValueNotifier<int>(60);
    addTearDown(count.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: count,
            builder: (context, itemCount, child) => ListView.builder(
              controller: scrollController,
              itemCount: itemCount,
              itemBuilder: (context, index) =>
                  SizedBox(height: 120, child: Text('item $index')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    scrollController.jumpTo(scrollController.position.maxScrollExtent);
    await tester.pump();
    expect(chatScroll.autoStickToBottom, isTrue);

    // 模拟流式正文变长：内容总高增加，滚动像素保持不动。
    count.value += 3;
    await tester.pump();
    final pixels = scrollController.position.pixels;
    // 位移 1 像素触发滚动通知，方向朝下、并非用户向上离开底部。
    scrollController.jumpTo(pixels + 1);
    await tester.pump();

    expect(
      chatScroll.autoStickToBottom,
      isTrue,
      reason: '内容变长不等于用户离开底部；清掉跟随会让生成结束后差一截（真机 gap=260）',
    );
  });

  testWidgets('用户主动向上滚动后，自动跟随仍然关闭', (tester) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final chatScroll = scroll_ctrl.ChatScrollController(
      scrollController: scrollController,
      onStateChanged: () {},
      getAutoScrollEnabled: () => true,
      getAutoScrollIdleSeconds: () => 3,
      getTopRevealInset: () => 0,
      isGenerating: () => false,
    );
    addTearDown(chatScroll.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: scrollController,
            itemCount: 60,
            itemBuilder: (context, index) =>
                SizedBox(height: 120, child: Text('item $index')),
          ),
        ),
      ),
    );
    await tester.pump();

    scrollController.jumpTo(scrollController.position.maxScrollExtent);
    await tester.pump();
    expect(chatScroll.autoStickToBottom, isTrue);

    chatScroll.handleUserScrollIntent();
    scrollController.jumpTo(scrollController.position.pixels - 400);
    await tester.pump();

    expect(chatScroll.autoStickToBottom, isFalse);

    // 导航按钮的隐藏计时器走完，避免测试结束时留下 pending timer。
    await tester.pump(const Duration(seconds: 3));
  });
}
