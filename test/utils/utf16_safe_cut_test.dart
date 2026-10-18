import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/utils/utf16_safe_cut.dart';

void main() {
  test('head and tail cuts do not split surrogate pairs', () {
    const value = 'ab😀cd';
    expect(truncateHeadUtf16Safe(value, 3), 'ab');
    expect(truncateTailUtf16Safe(value, 3), 'cd');
    expect(utf16SafeTailStartForMaxUnits(value, 3), 4);
  });

  test('tail cut point moves forward instead of splitting a pair', () {
    const value = 'ab😀cd';
    // 代理对占 [2,3)，切点 3 会把它拆开，因此前移到 4。
    expect(utf16SafeTailStart(value, 3), 4);
    expect(utf16SafeTailStart(value, 1), 1);
    expect(utf16SafeHeadEnd(value, 3), 2);
    expect(utf16SafeHeadEnd(value, 4), 4);
  });

  group('redistributeTextUtf16Safe', () {
    test('uses cumulative original lengths as cut points', () {
      expect(redistributeTextUtf16Safe('abcdef', const [3, 2]), ['abc', 'def']);
    });

    test('keeps a surrogate pair whole at its own boundary', () {
      expect(redistributeTextUtf16Safe('a😀', const [1, 1]), ['a', '😀']);
    });

    test('a pair crossing a cut stays in the earlier slot', () {
      expect(redistributeTextUtf16Safe('a😀b', const [2, 2]), ['a😀', 'b']);
    });

    test('the last slot receives the remainder', () {
      expect(redistributeTextUtf16Safe('xy', const [50, 50]), ['xy', '']);
    });
  });

  test('chunks cover the complete text without splitting emoji', () {
    const value = 'a😀b😀c';
    final chunks = splitUtf16SafeChunks(value, 3);
    expect(chunks, ['a😀', 'b😀', 'c']);
    expect(chunks.join(), value);
  });

  test('halves remain valid at an emoji boundary', () {
    const value = 'ab😀cd';
    final halves = splitUtf16SafeHalves(value);
    expect(halves.join(), value);
    expect(halves.every((part) => !part.contains('\uFFFD')), isTrue);
  });
}
