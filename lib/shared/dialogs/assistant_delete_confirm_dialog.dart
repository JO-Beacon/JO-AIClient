import 'package:flutter/material.dart';

import '../widgets/ios_checkbox.dart';

/// 删除助手时用户的选择。
///
/// 默认保留会话：它们会落到“未指定助手”，之后仍可手动移动到别的助手。
/// 只有主动勾选，才连同全部会话一起删除。
final class AssistantDeleteChoice {
  const AssistantDeleteChoice({required this.deleteConversations});

  final bool deleteConversations;
}

Future<AssistantDeleteChoice?> showAssistantDeleteConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  required String keepConversationsOption,
  required String cancelLabel,
  required String confirmLabel,
}) {
  var deleteConversations = false;
  return showDialog<AssistantDeleteChoice>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: cs.surface,
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(content),
              const SizedBox(height: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    setState(() => deleteConversations = !deleteConversations),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      IosCheckbox(
                        value: deleteConversations,
                        size: 20,
                        hitTestSize: 28,
                        enableHaptics: false,
                        onChanged: (value) =>
                            setState(() => deleteConversations = value),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          keepConversationsOption,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: cs.onSurface.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(cancelLabel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(
                AssistantDeleteChoice(deleteConversations: deleteConversations),
              ),
              child: Text(confirmLabel, style: TextStyle(color: cs.error)),
            ),
          ],
        ),
      );
    },
  );
}
