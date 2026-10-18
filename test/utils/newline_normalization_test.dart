import 'package:Kelivo/utils/newline_normalization.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeNewlines', () {
    test('leaves LF unchanged', () {
      expect(normalizeNewlines('a\nb'), 'a\nb');
      expect(identical(normalizeNewlines('a\nb'), 'a\nb'), isTrue);
    });

    test('collapses CRLF to LF', () {
      expect(normalizeNewlines('a\r\nb'), 'a\nb');
    });

    test('collapses a lone CR to LF', () {
      expect(normalizeNewlines('a\rb'), 'a\nb');
    });

    test('handles a mix of sources', () {
      expect(normalizeNewlines('a\r\nb\nc\rd'), 'a\nb\nc\nd');
    });

    test('turns U+2028 line separators into LF', () {
      expect(normalizeNewlines('a\u2028b'), 'a\nb');
    });

    test('turns U+2029 paragraph separators into LF', () {
      expect(normalizeNewlines('a\u2029b'), 'a\nb');
    });

    test('turns U+0085 next-line separators into LF', () {
      expect(normalizeNewlines('a\u0085b'), 'a\nb');
    });

    test('normalizes every supported separator in one pass', () {
      expect(
        normalizeNewlines('a\r\nb\rc\u2028d\u2029e\u0085f'),
        'a\nb\nc\nd\ne\nf',
      );
    });

    test('only LF text is left untouched, including identity', () {
      const text = 'a\nb\nc';
      expect(needsNewlineNormalization(text), isFalse);
      expect(identical(normalizeNewlines(text), text), isTrue);
    });

    test('reports the separators it can normalize', () {
      for (final text in [
        'a\rb',
        'a\r\nb',
        'a\u2028b',
        'a\u2029b',
        'a\u0085b',
      ]) {
        expect(needsNewlineNormalization(text), isTrue, reason: text);
      }
    });
  });

  group('NormalizeNewlinesFormatter', () {
    const formatter = NormalizeNewlinesFormatter();

    test('returns the value untouched when there is no CR', () {
      const value = TextEditingValue(
        text: 'a\nb',
        selection: TextSelection.collapsed(offset: 3),
      );
      expect(formatter.formatEditUpdate(TextEditingValue.empty, value), value);
    });

    test('normalizes CRLF and moves the caret with the shorter text', () {
      const value = TextEditingValue(
        text: 'a\r\nb',
        selection: TextSelection.collapsed(offset: 4),
      );
      final result = formatter.formatEditUpdate(TextEditingValue.empty, value);
      expect(result.text, 'a\nb');
      expect(result.selection.baseOffset, 3);
    });

    test('normalizes a lone CR', () {
      const value = TextEditingValue(
        text: 'a\rb',
        selection: TextSelection.collapsed(offset: 3),
      );
      final result = formatter.formatEditUpdate(TextEditingValue.empty, value);
      expect(result.text, 'a\nb');
      expect(result.selection.baseOffset, 3);
    });

    test('normalizes U+2028 without moving the caret', () {
      const value = TextEditingValue(
        text: 'a\u2028b',
        selection: TextSelection.collapsed(offset: 3),
      );
      final result = formatter.formatEditUpdate(TextEditingValue.empty, value);
      expect(result.text, 'a\nb');
      expect(result.selection.baseOffset, 3);
    });

    test('keeps a selection over normalized separators aligned', () {
      const value = TextEditingValue(
        text: 'a\u2028b\u2029c',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      );
      final result = formatter.formatEditUpdate(TextEditingValue.empty, value);
      expect(result.text, 'a\nb\nc');
      expect(result.selection.baseOffset, 0);
      expect(result.selection.extentOffset, 5);
    });
  });
}
