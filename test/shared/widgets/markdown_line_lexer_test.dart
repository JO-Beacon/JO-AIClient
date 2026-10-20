import 'package:Kelivo/shared/widgets/incremental_markdown_document.dart';
import 'package:Kelivo/shared/widgets/markdown_line_lexer.dart';
import 'package:flutter_test/flutter_test.dart';

String _unmatchedBacktickRuns({int maxRun = 200}) {
  final buffer = StringBuffer();
  for (var n = 1; n <= maxRun; n++) {
    if (n > 1) buffer.write(' ');
    buffer.write('`' * n);
  }
  return buffer.toString();
}

List<(int, int)> _spans(String text) => [
  for (final span in markdownScanDisplayMath(text).spans)
    (span.start, span.end),
];

void main() {
  tearDown(debugDisableMarkdownScanVisits);

  test('unclosed inline code does not hide a later display-math closer', () {
    const content = '`unclosed\n\$\$ `x` \$\$';
    expect(markdownEndsWithDisplayMath(content, content.length), isTrue);
  });

  test(
    'a mid-line details mention does not hide a later display-math closer',
    () {
      const content = 'Use <details> here\n\$\$b\$\$';
      expect(markdownEndsWithDisplayMath(content, content.length), isTrue);
    },
  );

  test('a line-leading details block does hide math inside it', () {
    const content = '<details>\n\$\$b\$\$\n</details>';
    expect(markdownEndsWithDisplayMath(content, content.length), isFalse);
  });

  test('fence markers are recognized before inline backticks', () {
    const content = '```\n`\$\$\n```\n\$\$b\$\$';
    expect(markdownEndsWithDisplayMath(content, content.length), isTrue);
  });

  for (final separator in const ['\u2028', '\u2029', '\r']) {
    test('$separator is a logical break for display math', () {
      final content = 'Text$separator\$\$b\$\$';
      expect(markdownEndsWithDisplayMath(content, content.length), isTrue);
    });
  }

  test('display-math walk visits stay linear on a long space line', () {
    final content = '${' ' * 4000}\n\$\$x\$\$';
    debugResetMarkdownScanVisits();
    expect(markdownEndsWithDisplayMath(content, content.length), isTrue);
    expect(
      debugMarkdownScanVisits,
      lessThanOrEqualTo(content.length * debugMarkdownScanVisitBudgetFactor),
    );
  });

  test('display-math walk visits stay linear on unmatched backtick runs', () {
    final content = '${_unmatchedBacktickRuns()}\n\$\$x\$\$';
    debugResetMarkdownScanVisits();
    expect(markdownEndsWithDisplayMath(content, content.length), isTrue);
    expect(
      debugMarkdownScanVisits,
      lessThanOrEqualTo(content.length * debugMarkdownScanVisitBudgetFactor),
    );
  });

  test('a longer fence is not closed by a shorter run of the same marker', () {
    const content = '````\n```\n\$\$b\$\$\n````';
    expect(markdownEndsWithDisplayMath(content, content.length), isFalse);
  });

  test('a longer fence still allows math after a matching closer', () {
    const content = '````\n```\n\$\$b\$\$\n````\n\$\$c\$\$';
    expect(markdownEndsWithDisplayMath(content, content.length), isTrue);
  });

  test('a tilde fence is not closed by backticks', () {
    const content = '~~~\n```\n\$\$b\$\$\n~~~';
    expect(markdownEndsWithDisplayMath(content, content.length), isFalse);
  });

  test(
    'display-math walk visits stay linear on many short inline-code spans',
    () {
      final spans = List<String>.filled(3000, '`x`').join(' ');
      expect(debugBacktickJumpSlotCount(spans), 3000);
      debugResetMarkdownScanVisits();
      final content = '$spans\n\$\$y\$\$';
      expect(markdownEndsWithDisplayMath(content, content.length), isTrue);
      expect(
        debugMarkdownScanVisits,
        lessThanOrEqualTo(content.length * debugMarkdownScanVisitBudgetFactor),
      );
    },
  );

  test('backtick jump table scales with run count on a long line', () {
    final line = '${'a' * 200000}`x`${'b' * 200000}';
    expect(debugBacktickJumpSlotCount(line), 1);
    debugResetMarkdownScanVisits();
    final content = '$line\n\$\$x\$\$';
    expect(markdownEndsWithDisplayMath(content, content.length), isTrue);
    expect(
      debugMarkdownScanVisits,
      lessThanOrEqualTo(content.length * debugMarkdownScanVisitBudgetFactor),
    );
  });

  test('a successful dollar span discards an inner bracket opener', () {
    const content = '\$\$\n\\[\n\$\$\n\\]';
    expect(markdownEndsWithDisplayMath(content, content.length), isFalse);
  });

  test('a successful bracket span discards an inner dollar opener', () {
    const content = '\\[\n\$\$\n\\]\n\$\$';
    expect(markdownEndsWithDisplayMath(content, content.length), isFalse);
  });

  test('an unclosed bracket does not hide a later dollar span', () {
    const content = '\\[\n\$\$\nx\n\$\$';
    expect(markdownEndsWithDisplayMath(content, content.length), isTrue);
  });

  test('an unclosed dollar does not hide a later bracket span', () {
    const content = '\$\$\n\\[\nx\n\\]';
    expect(markdownEndsWithDisplayMath(content, content.length), isTrue);
  });

  test('a tailed closer does not end a later successful dollar span', () {
    const content = '\$\$\n\$\$ tail\n\ninside\n\$\$';
    expect(markdownEndsWithDisplayMath(content, content.length), isTrue);
  });

  test('crossed nested openers end on the outer bracket closer', () {
    const content = '\\[\n\$\$\n\\[\n\$\$\n\\]';
    expect(markdownEndsWithDisplayMath(content, content.length), isTrue);
  });

  test('a successful dollar span treats an inner fence marker as content', () {
    const content = '\$\$\n```\n\$\$';
    expect(markdownScanDisplayMath(content).spans, hasLength(1));
  });

  test('an earlier unclosed fence still hides later math', () {
    const content = '```\n\$\$\nx\n\$\$';
    expect(markdownScanDisplayMath(content).spans, isEmpty);
    expect(markdownEndsWithDisplayMath(content, content.length), isFalse);
  });

  test('an unclosed dollar opener does not occupy later details', () {
    const content = '\$\$\n<details><summary>s</summary>body</details>';
    expect(markdownScanDisplayMath(content).spans, isEmpty);
    final registry = MarkdownDetailsRegistry(enableMath: true);
    expect(registry.lookup(registry.rewrite(content)), isNotNull);
  });

  test(
    'details inside a successful dollar span do not steal a later block',
    () {
      const source =
          '\$\$\n<details>\n\$\$\n'
          '<details><summary>real</summary>body</details>';
      final registry = MarkdownDetailsRegistry(enableMath: true);
      expect(registry.lookup(registry.rewrite(source))!.summary, 'real');
    },
  );

  test('math inside outer details does not close the outer block', () {
    const source =
        '<details><summary>outer</summary>\n'
        '\$\$\n'
        '  \$\$ </details>\n'
        '\$\$\n'
        'body\n'
        '</details>';
    final registry = MarkdownDetailsRegistry(enableMath: true);
    final block = registry.lookup(registry.rewrite(source));
    expect(block, isNotNull);
    expect(block!.summary, 'outer');
    expect(block.body, contains('body'));
  });

  test('details after a closed formula still extract', () {
    const source =
        '\$\$\nx\n\$\$\n'
        '<details><summary>real</summary>body</details>';
    final registry = MarkdownDetailsRegistry(enableMath: true);
    expect(registry.lookup(registry.rewrite(source))!.summary, 'real');
  });

  test('appending plain text keeps later spans after an unresolved opener', () {
    const first = '\$\$\n```\ncode\n```\n\\[\nx\n\\]\n';
    const next = '${first}plain tail';
    final scanner = MarkdownDisplayMathScanner();
    expect([
      for (final span in scanner.synchronize(first).spans)
        (span.start, span.end),
    ], _spans(first));
    expect([
      for (final span in scanner.synchronize(next).spans)
        (span.start, span.end),
    ], _spans(next));
  });

  test('chunked scanner spans match one-shot on math-dense input', () {
    final scanner = MarkdownDisplayMathScanner();
    var source = '';
    for (var i = 0; i < 20; i++) {
      source += '\$\$\nx$i\n\$\$\n\n';
      expect([
        for (final span in scanner.synchronize(source).spans)
          (span.start, span.end),
      ], _spans(source));
    }
  });

  test('single-shot and chunked scans stay linear on ordinary text', () {
    _expectLinearScan((_) => '0123456789abcdef', chunks: 200);
  });

  test('single-shot and chunked scans stay linear on math-dense text', () {
    _expectLinearScan((_) => '\$\$\nx\n\$\$\n\n', chunks: 80);
  });

  test('single-shot and chunked scans stay linear on fence-dense text', () {
    _expectLinearScan((_) => '```\nx\n```\n\n', chunks: 80);
  });

  test('fence indent is horizontal whitespace for the scanner', () {
    for (final indent in const [' ', '  ', '\t', ' \t']) {
      final probed = '$indent```\n\$\$\nx\n\$\$\n```';
      expect(
        markdownScanDisplayMath(probed).spans.isEmpty,
        isTrue,
        reason: 'scanner indent ${indent.codeUnits}',
      );
    }
    for (final indent in const ['\u00a0', '\u2003', '\u3000']) {
      final probed = '$indent```\n\$\$\nx\n\$\$\n```';
      expect(
        markdownScanDisplayMath(probed).spans.isEmpty,
        isFalse,
        reason: 'scanner indent ${indent.codeUnits}',
      );
    }
  });

  test('details walker accepts a one-line block', () {
    const source = '<details><summary>s</summary>body</details>';
    final walker = MarkdownDetailsWalker()..consumeText(source);
    expect(walker.depth, 0);
    expect(walker.overflowed, isFalse);
    expect(markdownDetailsExtent(source) >= 0, isTrue);
    expect(markdownParseDetails(source) != null, isTrue);
  });

  test('details walker accepts six nested layers', () {
    final source = _nestedDetails(6);
    final walker = MarkdownDetailsWalker()..consumeText(source);
    expect(walker.depth, 0);
    expect(markdownParseDetails(source) != null, isTrue);
  });

  test('a seventh nested layer overflows', () {
    final source = _nestedDetails(7);
    final walker = MarkdownDetailsWalker()..consumeText(source);
    expect(walker.depth, 0);
    expect(walker.overflowed, isTrue);
    expect(markdownDetailsExtent(source), -1);
    expect(markdownParseDetails(source), isNull);
    expect(MarkdownDetailsRegistry().rewrite(source), source);
  });

  test('unclosed details with many code spans stays linear', () {
    final source =
        '<details><summary>s</summary>${List.filled(20, '`x`').join(' ')}';
    _expectUnclosedDetailsScan(source);
  });

  test('unclosed details with a long backtick run stays linear', () {
    for (final n in const [40, 60]) {
      _expectUnclosedDetailsScan('<details><summary>s</summary>${'`' * n}');
    }
  });

  test('splitter visits stay linear on unmatched backtick runs', () {
    final source = 'before\n\n${_unmatchedBacktickRuns()}\n\nafter';
    debugResetMarkdownScanVisits();
    final blocks = IncrementalMarkdownDocument().update(source);
    expect(blocks, hasLength(3));
    expect(
      debugMarkdownScanVisits,
      lessThanOrEqualTo(source.length * debugMarkdownScanVisitBudgetFactor),
    );
  });

  test('details rewrite replaces a complete block with a placeholder', () {
    const source = '<details><summary>s</summary>`a < b`</details>';
    final registry = MarkdownDetailsRegistry();
    final rewritten = registry.rewrite(source);
    expect(rewritten, isNot(source));
    expect(registry.hasIssuedPlaceholders, isTrue);
    final parsed = registry.lookup(rewritten)!;
    expect(parsed.summary, 's');
    expect(parsed.body, '`a < b`');
  });

  test('extract does not promote a closed block inside an unclosed outer', () {
    const source =
        '<details>\n<summary>A</summary>\nunclosed\n'
        '<details><summary>B</summary>body B</details>';
    final walker = MarkdownDetailsWalker()..consumeText(source);
    expect(walker.depth, 1);
    expect(MarkdownDetailsRegistry().rewrite(source), source);
  });

  test(
    'extract visits stay linear on consecutive unclosed details openers',
    () {
      final source = List.filled(100, '<details>').join('\n');
      expect(source.length, 999);
      debugResetMarkdownScanVisits();
      expect(MarkdownDetailsRegistry().rewrite(source), source);
      expect(
        debugMarkdownScanVisits,
        lessThanOrEqualTo(source.length * debugMarkdownScanVisitBudgetFactor),
      );
    },
  );

  test('a same-line tail is not rewritten to a placeholder', () {
    const source = '<details><summary>s</summary>body</details> tail';
    expect(markdownParseDetails(source), isNotNull);
    expect(MarkdownDetailsRegistry().rewrite(source), source);
  });

  test('trailing spaces stay a block-boundary placeholder', () {
    const source = '<details><summary>s</summary>body</details>  ';
    final registry = MarkdownDetailsRegistry();
    final rewritten = registry.rewrite(source);
    expect(registry.hasIssuedPlaceholders, isTrue);
    expect(registry.lookup(rewritten)!.summary, 's');
  });

  test('same-line adjacent details are not rewritten', () {
    const source =
        '<details><summary>A</summary>a</details>'
        '<details><summary>B</summary>b</details>';
    expect(MarkdownDetailsRegistry().rewrite(source), source);
  });

  test('extract skips details inside display math when math is enabled', () {
    const source = '\$\$\n<details><summary>s</summary>body</details>\n\$\$';
    expect(MarkdownDetailsRegistry(enableMath: true).rewrite(source), source);
    final off = MarkdownDetailsRegistry(enableMath: false);
    expect(off.rewrite(source), isNot(source));
    expect(off.hasIssuedPlaceholders, isTrue);
  });
}

void _expectLinearScan(
  String Function(int index) chunk, {
  required int chunks,
}) {
  final full = StringBuffer();
  for (var i = 0; i < chunks; i++) {
    full.write(chunk(i));
  }
  final text = full.toString();
  debugResetMarkdownScanVisits();
  markdownScanDisplayMath(text);
  expect(
    debugMarkdownScanVisits,
    lessThanOrEqualTo(text.length * debugMarkdownScanVisitBudgetFactor),
  );

  final scanner = MarkdownDisplayMathScanner();
  var source = '';
  debugResetMarkdownScanVisits();
  for (var i = 0; i < chunks; i++) {
    source += chunk(i);
    scanner.synchronize(source);
  }
  expect(
    debugMarkdownScanVisits,
    lessThanOrEqualTo(source.length * debugMarkdownScanVisitBudgetFactor),
  );
}

void _expectUnclosedDetailsScan(String source) {
  debugResetMarkdownScanVisits();
  expect(markdownDetailsExtent(source), -1);
  final walker = MarkdownDetailsWalker()..consumeText(source);
  expect(walker.depth, 1);
  expect(markdownParseDetails(source), isNull);
  expect(
    debugMarkdownScanVisits,
    lessThanOrEqualTo(source.length * debugMarkdownScanVisitBudgetFactor),
  );
}

String _nestedDetails(int levels) {
  final out = StringBuffer();
  for (var i = 1; i <= levels; i++) {
    out.writeln('<details>');
    out.writeln('<summary>L$i</summary>');
  }
  out.write('deep-body');
  for (var i = 0; i < levels; i++) {
    out.write('</details>');
    if (i < levels - 1) out.writeln();
  }
  return out.toString();
}
