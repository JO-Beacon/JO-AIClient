import '../../../core/models/chat_message.dart';

/// 一个逻辑时间线槽位的不可变、预计算输入。
///
/// 渲染器代码在构建单行时不得扫描完整消息列表或排序修订。
final class MessageRenderModel {
  const MessageRenderModel({
    required this.slotId,
    required this.message,
    required this.isLatestCompleteAssistant,
  });

  final String slotId;
  final ChatMessage message;
  final bool isLatestCompleteAssistant;
}

final class MessageRenderModelProjector {
  const MessageRenderModelProjector._();

  static List<MessageRenderModel> project({
    required List<ChatMessage> messages,
  }) {
    var latestCompleteAssistantIndex = -1;
    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      if (message.role == 'assistant' && !message.isStreaming) {
        latestCompleteAssistantIndex = index;
        break;
      }
    }

    return List<MessageRenderModel>.unmodifiable([
      for (final (index, message) in messages.indexed)
        MessageRenderModel(
          slotId: message.id,
          message: message,
          isLatestCompleteAssistant: index == latestCompleteAssistantIndex,
        ),
    ]);
  }
}
