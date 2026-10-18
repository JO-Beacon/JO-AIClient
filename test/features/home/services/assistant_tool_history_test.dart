import 'dart:convert';

import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/features/home/services/assistant_tool_history.dart';
import 'package:flutter_test/flutter_test.dart';

ToolCallPart _call(String id, {Object? content, String name = 'lookup'}) =>
    ToolCallPart(
      jsonEncode({
        'id': id,
        'name': name,
        'arguments': {'id': id},
        if (content != null) 'content': content,
      }),
    );

void main() {
  group('buildAssistantToolHistory', () {
    test('一轮完成的调用与结果组成 assistant + tool 两条消息', () {
      final history = buildAssistantToolHistory([
        const ReasoningPart('想一想'),
        const TextPart('查一下'),
        _call('a', content: '结果 A'),
        const AssistantRoundEndPart(),
        const TextPart('结论'),
      ]);

      expect(history.messages.map((m) => m['role']).toList(), [
        'assistant',
        'tool',
      ]);
      final assistant = history.messages.first;
      expect(assistant['content'], '查一下');
      expect(assistant['reasoning_content'], '想一想');
      expect((assistant['tool_calls'] as List).single['id'], 'a');
      expect(history.messages.last['tool_call_id'], 'a');
      expect(history.messages.last['content'], '结果 A');
      // 工具之后的正文属于同一条回复，留在 content 里而不是重现顺序。
      expect(history.content, '结论');
      // `reasoning` 只汇总未闭合尾部的推理：已完成轮次的推理在消息里。
      expect(history.reasoning, isNull);
    });

    test('缺结果的轮次整轮不产出，但更早的完整轮次保留', () {
      final history = buildAssistantToolHistory([
        _call('a', content: '结果 A'),
        const AssistantRoundEndPart(),
        _call('b'), // 没有 content：用户中途取消
        const AssistantRoundEndPart(),
      ]);

      expect(history.messages.map((m) => m['role']).toList(), [
        'assistant',
        'tool',
      ]);
      expect((history.messages.first['tool_calls'] as List).single['id'], 'a');
    });

    test('只有推理没有工具时，不产出任何 assistant 消息', () {
      final history = buildAssistantToolHistory([
        const ReasoningPart('只是想'),
        const TextPart('说点什么'),
        const AssistantRoundEndPart(),
      ]);

      expect(history.messages, isEmpty);
      expect(history.content, '说点什么');
      expect(history.reasoning, '只是想');
    });

    test('损坏的工具载荷只跳过这一条，不影响其余部分', () {
      final history = buildAssistantToolHistory([
        const ToolCallPart('{坏掉的'),
        _call('a', content: '好结果'),
        const AssistantRoundEndPart(),
      ]);

      expect(history.messages.map((m) => m['role']).toList(), [
        'assistant',
        'tool',
      ]);
      expect((history.messages.first['tool_calls'] as List).single['id'], 'a');
    });

    test('缺少 id 或 name 的调用被丢弃', () {
      final history = buildAssistantToolHistory([
        const ToolCallPart('{"id":"","name":"lookup","content":"x"}'),
        const ToolCallPart('{"id":"a","name":"","content":"x"}'),
      ]);

      expect(history.messages, isEmpty);
    });

    test('轮次结束携带的推理详情写进对应的 assistant 消息', () {
      const details = [
        {'type': 'reasoning.text', 'text': 'r', 'signature': 'sig'},
      ];
      final history = buildAssistantToolHistory([
        const ReasoningPart('r'),
        _call('a', content: '结果'),
        const AssistantRoundEndPart(reasoningDetails: details),
      ]);

      expect(history.messages.first['reasoning_details'], details);
    });

    test('结束标记之后的正文不再并入已完成的轮次', () {
      final history = buildAssistantToolHistory([
        const TextPart('第一段'),
        _call('a', content: '结果'),
        const AssistantRoundEndPart(),
        const TextPart('第二段'),
      ]);

      expect(history.messages.first['content'], '第一段');
      expect(history.content, '第二段');
    });

    test('参数不是字符串时序列化为 JSON', () {
      final history = buildAssistantToolHistory([
        _call('a', content: '结果'),
        const AssistantRoundEndPart(),
      ]);

      final call = (history.messages.first['tool_calls'] as List).single;
      expect(jsonDecode((call['function'] as Map)['arguments']), {'id': 'a'});
    });
  });
}
