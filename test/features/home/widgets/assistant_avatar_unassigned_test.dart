import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/features/home/widgets/assistant_avatar.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';

void main() {
  testWidgets('未指定助手用区别于普通助手的图标，不显示首字母', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              AssistantAvatar(
                assistant: Assistant(
                  id: AssistantProvider.unassignedAssistantId,
                  name: 'Unassigned',
                ),
              ),
              AssistantAvatar(
                assistant: Assistant(id: 'normal', name: 'Normal'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Lucide.MessageCircleDashed), findsOneWidget);
    // 普通助手仍然显示首字母头像。
    expect(find.text('N'), findsOneWidget);
    expect(find.text('U'), findsNothing);
  });
}
