import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import 'long_message_editor.dart';

/// 多行正文输入框：跟随“长文本使用按行编辑器”开关。
///
/// 开关关闭、或文本未达到阈值时，内部仍由 [LongMessageEditor] 渲染原生输入框，
/// 外观与普通 TextField 一致；只有长文本才切换为按行编辑器。
class LongTextField extends StatelessWidget {
  const LongTextField({
    super.key,
    required this.controller,
    required this.decoration,
    this.minLines = 1,
    this.maxLines,
    this.expands = false,
    this.autofocus = false,
    this.readOnly = false,
    this.focusNode,
    this.style,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final int? minLines;
  final int? maxLines;
  final bool expands;
  final bool autofocus;
  final bool readOnly;
  final FocusNode? focusNode;
  final TextStyle? style;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return LongMessageEditor(
      controller: controller,
      decoration: decoration,
      minLines: minLines,
      maxLines: maxLines,
      expands: expands,
      autofocus: autofocus,
      readOnly: readOnly,
      focusNode: focusNode,
      style: style,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      inputFormatters: inputFormatters,
      enabled: context.watch<SettingsProvider>().useLongMessageEditor,
    );
  }
}
