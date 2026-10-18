import '../../../core/models/message_part.dart';

/// 编辑保存前对“续答分界”做一次结构规整。
///
/// 两段分界之间如果已经没有内容（部件删光了，或只剩空正文），这一段在回放里
/// 不存在任何可交代的东西：它既没有工具调用、也没有文字。此时保留它只会留下
/// 一个携带“推理详情”却永远不会被读到的空标记，所以直接丢掉。
///
/// 规则：
/// - 只保留“前面确实有内容”的分界；连续多个分界保留第一个。
/// - 空正文（`TextPart('')`）不算内容。
/// - 末尾分界照旧保留（它标记最后一轮的结束，不属于空段规整的范畴）。
List<MessagePart> normalizeRoundBoundaries(List<MessagePart> parts) {
  final out = <MessagePart>[];
  var hasContent = false;
  for (final part in parts) {
    if (part is AssistantRoundEndPart) {
      if (!hasContent) continue;
      // 连续分界：前面的已把内容切走，后面这些都在空段上。
      if (out.isNotEmpty && out.last is AssistantRoundEndPart) continue;
      out.add(part);
      hasContent = false;
      continue;
    }
    if (_isContent(part)) hasContent = true;
    out.add(part);
  }
  return out;
}

bool _isContent(MessagePart part) => switch (part) {
  TextPart(:final text) => text.isNotEmpty,
  ReasoningPart(:final text) => text.isNotEmpty,
  _ => true,
};
