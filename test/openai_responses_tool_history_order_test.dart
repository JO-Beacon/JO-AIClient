import 'dart:convert';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/providers/openai/openai_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Responses 协议把一条助手消息拆成两种条目：正文是 `message`，
/// 调用是 `function_call`，结果紧随其后是 `function_call_output`。
/// 这三者的相对顺序必须稳定，否则供应商会把“结果”算到别人的调用上。
///
/// 回归点：正文曾经是在调用条目之后追加的，于是它夹在调用和结果中间。
ProviderConfig _responsesConfig() => ProviderConfig(
  id: 'ResponsesToolOrderTest',
  enabled: true,
  name: 'ResponsesToolOrderTest',
  apiKey: 'test-key',
  baseUrl: 'https://example.com/v1',
  providerType: ProviderKind.openai,
  useResponseApi: true,
);

Map<String, dynamic> _call(String id) => {
  'id': id,
  'type': 'function',
  'function': {'name': 'lookup', 'arguments': '{}'},
};

List<Map<String, dynamic>> _tools() => [
  {
    'type': 'function',
    'function': {
      'name': 'lookup',
      'parameters': {'type': 'object', 'properties': <String, Object?>{}},
    },
  },
];

Future<List<Map<String, dynamic>>> _captureInput(
  List<Map<String, dynamic>> messages, {
  String model = 'gpt-5',
}) async {
  final bodies = <Map<String, dynamic>>[];
  final client = MockClient((request) async {
    bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
    return http.Response(
      'data: ${jsonEncode({
        'type': 'response.completed',
        'response': {'output': <Object>[]},
      })}\n\ndata: [DONE]\n\n',
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  });
  addTearDown(client.close);
  await sendOpenAIStream(
    client,
    _responsesConfig(),
    model,
    messages,
    tools: _tools(),
  ).toList();
  return (bodies.single['input'] as List).cast<Map<String, dynamic>>();
}

int _assistantTextIndex(List<Map<String, dynamic>> input, String text) {
  return input.indexWhere(
    (item) =>
        item['type'] == 'message' &&
        item['role'] == 'assistant' &&
        jsonEncode(item['content']).contains(text),
  );
}

int _callIndex(List<Map<String, dynamic>> input, String id) {
  return input.indexWhere(
    (item) => item['type'] == 'function_call' && item['call_id'] == id,
  );
}

int _outputIndex(List<Map<String, dynamic>> input, String id) {
  return input.indexWhere(
    (item) => item['type'] == 'function_call_output' && item['call_id'] == id,
  );
}

void _expectCallFollowedByOutput(
  List<Map<String, dynamic>> input,
  String id, {
  String? assistantText,
}) {
  final call = _callIndex(input, id);
  expect(call, isNonNegative, reason: '缺少 $id 的调用条目');
  if (assistantText != null) {
    final text = _assistantTextIndex(input, assistantText);
    expect(text, isNonNegative, reason: '缺少助手正文「$assistantText」');
    expect(text, lessThan(call), reason: '助手正文必须排在它自己的调用之前，否则会夹在调用与结果之间');
  }
  expect(_outputIndex(input, id), call + 1, reason: '调用与它的结果之间不能再插入任何条目');
}

void main() {
  test('助手正文排在自己的调用之前，调用与结果相邻（只支持文本的模型）', () async {
    final input = await _captureInput([
      {'role': 'user', 'content': '先查一下'},
      {
        'role': 'assistant',
        'content': '查一下',
        'tool_calls': [_call('call_a')],
      },
      {'role': 'tool', 'tool_call_id': 'call_a', 'content': '结果 A'},
      {'role': 'user', 'content': '谢谢'},
    ], model: 'deepseek-chat');

    _expectCallFollowedByOutput(input, 'call_a', assistantText: '查一下');
  });

  test('助手正文排在自己的调用之前，调用与结果相邻（支持图片的模型）', () async {
    final input = await _captureInput([
      {'role': 'user', 'content': '先查一下'},
      {
        'role': 'assistant',
        'content': '查一下',
        'tool_calls': [_call('call_a')],
      },
      {'role': 'tool', 'tool_call_id': 'call_a', 'content': '结果 A'},
    ]);

    _expectCallFollowedByOutput(input, 'call_a', assistantText: '查一下');
  });

  test('多轮工具交换逐轮保持顺序，且轮次之间不交叉', () async {
    final input = await _captureInput([
      {'role': 'user', 'content': '第一轮'},
      {
        'role': 'assistant',
        'content': '查 A',
        'tool_calls': [_call('call_a')],
      },
      {'role': 'tool', 'tool_call_id': 'call_a', 'content': '结果 A'},
      {
        'role': 'assistant',
        'content': '查 B',
        'tool_calls': [_call('call_b')],
      },
      {'role': 'tool', 'tool_call_id': 'call_b', 'content': '结果 B'},
      {'role': 'user', 'content': '第二轮'},
    ]);

    _expectCallFollowedByOutput(input, 'call_a', assistantText: '查 A');
    _expectCallFollowedByOutput(input, 'call_b', assistantText: '查 B');
    expect(
      _callIndex(input, 'call_a'),
      lessThan(_callIndex(input, 'call_b')),
      reason: '两轮调用的先后不能颠倒',
    );
  });

  test('一条消息里的多个调用各自与结果相邻', () async {
    final input = await _captureInput([
      {'role': 'user', 'content': '两个都要查'},
      {
        'role': 'assistant',
        'content': '都查一下',
        'tool_calls': [_call('call_a'), _call('call_b')],
      },
      {'role': 'tool', 'tool_call_id': 'call_a', 'content': '结果 A'},
      {'role': 'tool', 'tool_call_id': 'call_b', 'content': '结果 B'},
    ]);

    final first = _callIndex(input, 'call_a');
    final second = _callIndex(input, 'call_b');
    expect(
      _assistantTextIndex(input, '都查一下'),
      lessThan(first),
      reason: '正文要排在这一批调用的最前面',
    );
    // 一批调用在协议里是“先全部 function_call、再按同序全部结果”，
    // 这里要的是：每个结果都在自己的调用之后，且两者相对顺序一致。
    expect(_outputIndex(input, 'call_a'), greaterThan(first));
    expect(_outputIndex(input, 'call_b'), greaterThan(second));
    expect(
      _outputIndex(input, 'call_a'),
      lessThan(_outputIndex(input, 'call_b')),
      reason: '结果的先后必须与调用一致，不能错配到另一个调用上',
    );
  });

  test('带图片的助手消息同样把正文排在自己的调用之前', () async {
    final input = await _captureInput([
      {'role': 'user', 'content': '看这张图再查'},
      {
        'role': 'assistant',
        'content': '看图 ![png](data:image/png;base64,iVBORw0KGgo=) 然后查一下',
        'tool_calls': [_call('call_a')],
      },
      {'role': 'tool', 'tool_call_id': 'call_a', 'content': '结果 A'},
    ]);

    _expectCallFollowedByOutput(input, 'call_a', assistantText: '然后查一下');
  });

  test('不支持图片的模型上，带图片引用的助手消息同样保持顺序', () async {
    final input = await _captureInput([
      {'role': 'user', 'content': '看这张图再查'},
      {
        'role': 'assistant',
        'content': '看图 ![png](data:image/png;base64,iVBORw0KGgo=) 然后查一下',
        'tool_calls': [_call('call_a')],
      },
      {'role': 'tool', 'tool_call_id': 'call_a', 'content': '结果 A'},
    ], model: 'deepseek-chat');

    _expectCallFollowedByOutput(input, 'call_a', assistantText: '然后查一下');
  });

  test('没有正文的调用消息也能正常取到结果', () async {
    final input = await _captureInput([
      {'role': 'user', 'content': '查一下'},
      {
        'role': 'assistant',
        'content': '',
        'tool_calls': [_call('call_a')],
      },
      {'role': 'tool', 'tool_call_id': 'call_a', 'content': '结果 A'},
    ]);

    _expectCallFollowedByOutput(input, 'call_a');
    expect(
      input.where(
        (item) => item['type'] == 'message' && item['role'] == 'assistant',
      ),
      isEmpty,
      reason: '没有正文就不该凭空造一条空消息',
    );
  });
}
