import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/api/chat_api_helpers.dart';

/// `parseTextAndImages` 的围栏/行内代码处理契约。
///
/// 两条必须成立的性质：
/// 1. **文本绝不丢**：围栏是否闭合，原文都要按原样保留（现在的实现用
///    "逐字符写出 + `closed` 标志"，换成上游的 `indexOf` / `substring` 写法时必须逐字一致）。
/// 2. **代码块与行内代码里的 Markdown 图片不得被提取**：这正是跳过它们的唯一目的。
///
/// 这里统一用 `data:` URL 表达图片：它不需要联网也会被当作图片处理，
/// 而远程 http(s) 链接要经过实际可访问性校验（测试环境下必然失败）。
Future<ParsedTextAndImages> parse(String raw) {
  return parseTextAndImages(
    raw,
    allowRemoteImages: true,
    allowLocalImages: true,
    keepRemoteMarkdownText: false,
  );
}

const _inlineImage = '![a](data:image/png;base64,QUJD)';
const _innerImage = '![inner](data:image/png;base64,SU5ORVI=)';
const _outerImage = '![outer](data:image/png;base64,T1VURVI=)';
const _afterImage = '![after](data:image/png;base64,QUZURVI=)';

void main() {
  test('对照：围栏外的 Markdown 图片会被提取', () async {
    final parsed = await parse('看图 $_inlineImage 谢谢');

    expect(parsed.images, hasLength(1));
    expect(parsed.images.single.kind, 'data');
    // data URL 不进正文。
    expect(parsed.text, isNot(contains('data:image/png')));
    expect(parsed.text, contains('看图'));
    expect(parsed.text, contains('谢谢'));
  });

  test('闭合围栏内的图片不被提取，围栏外的图片照常提取', () async {
    final parsed = await parse('前言\n```\n$_innerImage\n```\n尾巴 $_outerImage');

    expect(parsed.images, hasLength(1));
    expect(parsed.images.single.src, 'data:image/png;base64,T1VURVI=');
    // 围栏内那段的原文照旧保留。
    expect(parsed.text, contains(_innerImage));
    expect(parsed.text, contains('```'));
    expect(parsed.text, contains('前言'));
    expect(parsed.text, contains('尾巴'));
  });

  test('未闭合围栏：图片不被提取，且剩余文本一字不丢', () async {
    const raw = '前言\n```dart\nfinal x = 1;\n$_innerImage\n没闭合';
    final parsed = await parse(raw);

    expect(parsed.images, isEmpty);
    expect(parsed.text, contains('```dart'));
    expect(parsed.text, contains('final x = 1;'));
    expect(parsed.text, contains(_innerImage));
    expect(parsed.text, contains('没闭合'));
    expect(parsed.text, contains('前言'));
  });

  test('开围栏行后没有换行也能原样保留', () async {
    final parsed = await parse('```');

    expect(parsed.images, isEmpty);
    expect(parsed.text, contains('```'));
  });

  test('波浪号围栏同样生效', () async {
    final parsed = await parse('~~~\n$_innerImage\n~~~\n');

    expect(parsed.images, isEmpty);
    expect(parsed.text, contains(_innerImage));
    expect(parsed.text, contains('~~~'));
  });

  test('行内代码里的图片不被提取', () async {
    final parsed = await parse('看这个 `$_inlineImage` 就行');

    expect(parsed.images, isEmpty);
    expect(parsed.text, contains(_inlineImage));
    expect(parsed.text, contains('看这个'));
    expect(parsed.text, contains('就行'));
  });

  test('行内代码未闭合：内容同样原样保留', () async {
    final parsed = await parse('看这个 `$_inlineImage');

    expect(parsed.images, isEmpty);
    expect(parsed.text, contains(_inlineImage));
  });

  test('围栏之后的普通图片仍会被提取', () async {
    final parsed = await parse('```\ncode\n```\n$_afterImage');

    expect(parsed.images, hasLength(1));
    expect(parsed.images.single.src, 'data:image/png;base64,QUZURVI=');
    expect(parsed.text, contains('code'));
  });
}
