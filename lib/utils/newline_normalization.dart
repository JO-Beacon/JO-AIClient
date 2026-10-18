import 'package:flutter/services.dart';

/// 需要归一的字符：`\r` 参与组成 CRLF／CR，另外三个是“看起来换行、
/// 却不是 `\n`”的分隔符。
///
/// - U+2028 LINE SEPARATOR、U+2029 PARAGRAPH SEPARATOR：Unicode 里的强制
///   断行，渲染上就是换行，但 `split('\n')`、`LineSplitter` 都不认——于是
///   标题、预览、导出这类按行处理的功能会把它当同一行；
/// - U+0085 NEXT LINE：同上，只是更少见。
final RegExp _lineBreaks = RegExp('[\r\u2028\u2029\u0085]');

/// 文本里是否含有需要归一的换行。
bool needsNewlineNormalization(String text) => _lineBreaks.hasMatch(text);

/// 把各种换行统一成 `\n`（LF）。
///
/// Windows 剪贴板给出的换行是 `\r\n`，部分来源还可能只剩一个 `\r`。
/// Flutter 里孤立的 `\r` **不产生换行**，会变成看不见、却需要删两次的字符；
/// `\r\n` 又可能把 `\r` 渲染成一个空格。键入的 Enter 本身是 `\n`，只有粘贴
/// 这类外部文本会带进来，所以统一在输入边界做归一化。
///
/// U+2028／U+2029／U+0085 一并归一成 `\n`：它们在排版上会断行，却不参与按
/// `\n` 的切分，留着会让“显示一个换行、实际不是换行”长期存在；按行编辑器
/// 也只按 `\n` 切行。导入与迁移同样调用这里，保证库里只存 LF。
String normalizeNewlines(String text) {
  if (!needsNewlineNormalization(text)) return text;
  return text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\u2028', '\n')
      .replaceAll('\u2029', '\n')
      .replaceAll('\u0085', '\n');
}

/// 覆盖键入与粘贴的换行归一化输入格式器。
///
/// 框架内置的粘贴同样会经过 [TextInputFormatter]，因此这个格式器能覆盖
/// 默认粘贴路径；绕开输入系统直接改 controller 的路径需要显式调用
/// [normalizeNewlines]。
class NormalizeNewlinesFormatter extends TextInputFormatter {
  const NormalizeNewlinesFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final source = newValue.text;
    if (!needsNewlineNormalization(source)) return newValue;
    final text = normalizeNewlines(source);

    int mapOffset(int offset) {
      final clamped = offset.clamp(0, source.length);
      return normalizeNewlines(source.substring(0, clamped)).length;
    }

    final selection = newValue.selection;
    final mappedSelection = selection.isValid
        ? TextSelection(
            baseOffset: mapOffset(selection.baseOffset),
            extentOffset: mapOffset(selection.extentOffset),
            affinity: selection.affinity,
          )
        : selection;
    return TextEditingValue(text: text, selection: mappedSelection);
  }
}
