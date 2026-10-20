import '../../../core/models/message_part.dart';

/// 对“续答分界”做一次结构规整。
///
/// 编辑面板删掉部件后用它即时更新列表；保存前再用它做一次兜底。
/// 两段分界之间如果一个部件都没有（全被删掉），这一段在回放里
/// 不存在任何可交代的东西，保留它只会留下一个永远不会被读到的空标记，
/// 所以直接丢掉。
///
/// “空段”只按“部件是否还存在”判断，不看正文是否为空：
/// 把一段正文清空但留着部件，不算空段，分界照旧保留。
/// - 只保留“前面确实还有部件”的分界；连续多个分界保留第一个。
/// - 末尾分界照旧保留（它标记最后一轮的结束）。
List<MessagePart> normalizeRoundBoundaries(List<MessagePart> parts) {
  final dropped = droppedRoundBoundaryIndices(parts);
  if (dropped.isEmpty) return List<MessagePart>.of(parts);
  final skip = dropped.toSet();
  return [
    for (var i = 0; i < parts.length; i++)
      if (!skip.contains(i)) parts[i],
  ];
}

/// 返回需要收掉的“续答分界”下标。
///
/// 编辑面板在删掉部件后用它立即更新列表，保存前又用它做一次兜底；
/// 两边共用同一条规则，避免两套判断逐渐分叉。
List<int> droppedRoundBoundaryIndices(List<MessagePart> parts) {
  final dropped = <int>[];
  var hasParts = false;
  var lastKeptIsBoundary = false;
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (part is AssistantRoundEndPart) {
      if (!hasParts || lastKeptIsBoundary) {
        dropped.add(i);
        continue;
      }
      lastKeptIsBoundary = true;
      hasParts = false;
      continue;
    }
    hasParts = true;
    lastKeptIsBoundary = false;
  }
  return dropped;
}
