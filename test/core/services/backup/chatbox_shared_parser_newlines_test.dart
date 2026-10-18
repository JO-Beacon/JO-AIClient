import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/services/backup/chatbox_shared_parser.dart';

/// 外部文本里的换行只允许以 `\n` 进入存储：CRLF、孤立 CR，以及
/// “看起来换行、按 `\n` 切分又不认”的 U+2028／U+2029／U+0085。
void main() {
  // 一行里把五种换行都放进去：CRLF、CR、U+2028、U+2029、U+0085。
  const mixed = 'a\r\nb\rc\u2028d\u2029e\u0085f';

  List<String> textsOf(List<MessagePart> parts) => parts
      .whereType<TextPart>()
      .map((part) => part.text)
      .toList(growable: false);

  List<String> reasoningsOf(List<MessagePart> parts) => parts
      .whereType<ReasoningPart>()
      .map((part) => part.text)
      .toList(growable: false);

  void expectLfOnly(Iterable<String> values) {
    for (final value in values) {
      expect(value.contains('\r'), isFalse, reason: '残留 CR：$value');
      expect(value.contains('\u2028'), isFalse, reason: '残留 U+2028：$value');
      expect(value.contains('\u2029'), isFalse, reason: '残留 U+2029：$value');
      expect(value.contains('\u0085'), isFalse, reason: '残留 U+0085：$value');
    }
  }

  test('contentParts 文本片段统一成 LF', () {
    final parts = ChatboxSharedParser.extractMessageParts(<String, dynamic>{
      'contentParts': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': mixed},
      ],
    }, roleHint: 'user');

    final texts = textsOf(parts);
    expect(texts, isNotEmpty);
    expectLfOnly(texts);
    expect(texts.join(), contains('a\nb\nc\nd\ne\nf'));
  });

  test('旧版 content 回退路径统一成 LF', () {
    final parts = ChatboxSharedParser.extractMessageParts(<String, dynamic>{
      'content': mixed,
    }, roleHint: 'user');

    final texts = textsOf(parts);
    expect(texts, ['a\nb\nc\nd\ne\nf']);
    expectLfOnly(texts);
  });

  test('reasoning 片段与旧版 reasoningContent 统一成 LF', () {
    final structured = ChatboxSharedParser.extractMessageParts(
      <String, dynamic>{
        'contentParts': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'reasoning', 'text': mixed},
          <String, dynamic>{'type': 'text', 'text': '正文'},
        ],
      },
      roleHint: 'assistant',
    );
    expectLfOnly(reasoningsOf(structured));
    expect(reasoningsOf(structured).single, 'a\nb\nc\nd\ne\nf');

    final legacy = ChatboxSharedParser.extractMessageParts(<String, dynamic>{
      'content': '正文',
      'reasoningContent': mixed,
    }, roleHint: 'assistant');
    expect(reasoningsOf(legacy).single, 'a\nb\nc\nd\ne\nf');
    expectLfOnly(reasoningsOf(legacy));
  });
}
