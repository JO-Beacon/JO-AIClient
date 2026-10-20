import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/message_part.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../desktop/widgets/desktop_dialog_style.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/long_message_editor.dart';
import '../../../theme/app_font_weights.dart';
import '../../../utils/newline_normalization.dart';
import '../utils/round_structure.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';
import 'message_attachment_editor.dart';

/// 单个文本部件编辑框最多显示的行数，超出后在编辑框内部滚动。
///
/// 这个上限不能去掉改成“不限高”：编辑框所在的列表是自适应高度的，不限高时
/// 它会把内容整个撑开、自己永远不可滚，滚轮只能去滚外层的滚动容器；而 Flutter
/// 在“按住拖拽选择的同时外层发生滚动”这条路径上对选区起点的补偿是错的
/// （flutter/flutter#69296），表现为选中的范围会跑偏。限高之后编辑框自身可滚，
/// 滚轮落在编辑框内，走的是框架处理正确的那条路径。
/// 需要通读长内容时用标题栏的放大按钮打开大窗口。
const int _maxPartEditorLines = 8;

/// 节点级部件编辑器：正文可编辑，思考和工具部件只读但可移动/删除。
class MessagePartsEditor extends StatefulWidget {
  const MessagePartsEditor({
    super.key,
    required this.parts,
    required this.onChanged,
  });

  final List<MessagePart> parts;
  final ValueChanged<List<MessagePart>> onChanged;

  @override
  State<MessagePartsEditor> createState() => _MessagePartsEditorState();
}

class _MessagePartsEditorState extends State<MessagePartsEditor> {
  late List<MessagePart> _parts;
  // 每个部件给一个稳定编号，输入框缓存按编号存——不按位置存。
  // 否则删掉上面的部件后，下面那个框会把上一个框的内容拿过来。
  late List<int> _partKeys;
  int _nextPartKey = 0;
  final Map<int, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _resetParts(widget.parts);
  }

  @override
  void didUpdateWidget(covariant MessagePartsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.parts, widget.parts)) return;
    // 父级每敲一个字都会回传一份新列表。只要部件种类与数量没变，就只换内容，
    // 不重建编号与输入框：重建会让正在输入的框失去焦点，安卓上表现为
    // 敲一个字软键盘就收起来。
    if (_sameStructure(widget.parts)) {
      _parts = List<MessagePart>.of(widget.parts);
      _syncPartKeys();
      return;
    }
    _resetParts(widget.parts);
  }

  bool _sameStructure(List<MessagePart> next) {
    if (next.length != _parts.length) return false;
    for (var i = 0; i < next.length; i++) {
      if (next[i].runtimeType != _parts[i].runtimeType) return false;
    }
    return true;
  }

  void _resetParts(List<MessagePart> parts) {
    _parts = List<MessagePart>.of(parts);
    _partKeys = [for (var i = 0; i < _parts.length; i++) _nextPartKey++];
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }

  /// 附件编辑器会整体换一份列表；文字部件的位置不变，只补/收尾部编号。
  void _syncPartKeys() {
    while (_partKeys.length < _parts.length) {
      _partKeys.add(_nextPartKey++);
    }
    if (_partKeys.length > _parts.length) {
      for (final key in _partKeys.sublist(_parts.length)) {
        _controllers.remove(key)?.dispose();
      }
      _partKeys = _partKeys.sublist(0, _parts.length);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(int key, String text) {
    final normalized = normalizeNewlines(text);
    final controller = _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: normalized),
    );
    if (controller.text != normalized && !_editing(key)) {
      controller.text = normalized;
    }
    return controller;
  }

  bool _editing(int key) => _controllers[key]?.selection.isValid == true;

  void _emit() => widget.onChanged(List<MessagePart>.unmodifiable(_parts));

  Future<void> _remove(int index) async {
    // 分界是结构信息，不是内容：不允许单独删除。
    // 但删掉某个段的最后一个部件后，空出来的分界会立即从列表里消失，
    // 不需要等到保存。
    if (_parts[index] is AssistantRoundEndPart) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: Theme.of(dctx).colorScheme.surface,
        title: Text(l10n.messageEditDeletePartConfirmTitle),
        content: Text(l10n.messageEditDeletePartConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(l10n.messageEditCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(l10n.messageEditDeletePart),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final key = _partKeys.removeAt(index);
    _parts.removeAt(index);
    _controllers.remove(key)?.dispose();
    _dropEmptyRoundBoundaries();
    _emit();
    setState(() {});
  }

  /// 删完部件后，把因此变空的分界一并收掉；不写库，只改编辑中的列表。
  void _dropEmptyRoundBoundaries() {
    final dropped = droppedRoundBoundaryIndices(_parts);
    if (dropped.isEmpty) return;
    for (final index in dropped.reversed) {
      final key = _partKeys.removeAt(index);
      _parts.removeAt(index);
      _controllers.remove(key)?.dispose();
    }
  }

  void _addText() {
    _parts.add(const TextPart(''));
    _partKeys.add(_nextPartKey++);
    _emit();
    setState(() {});
  }

  /// 在大窗口中编辑（正文）或查看（思考 / 工具等只读部件）。
  Future<void> _expandPart(int index) async {
    final part = _parts[index];
    final key = _partKeys[index];
    final l10n = AppLocalizations.of(context)!;
    final editable = part is TextPart;
    final initial = part is TextPart
        ? (_controllers[key]?.text ?? part.text)
        : _partSummary(part);
    final title = '${index + 1} ${_partLabel(l10n, part)}';
    final next = await showMessagePartExpandedEditor(
      context,
      title: title,
      initialText: initial,
      readOnly: !editable,
    );
    if (!mounted || next == null || !editable || next == initial) return;
    _parts[index] = TextPart(next);
    _controllers[key]?.text = next;
    _emit();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 编辑列表只展示可编辑／可看懂的内容；分界不出现在界面上，
    // 但真实下标仍指向 _parts，删除与展开都按真实下标操作。
    final visibleParts = <({int index, MessagePart part})>[
      for (var i = 0; i < _parts.length; i++)
        if (_parts[i] is! AssistantRoundEndPart) (index: i, part: _parts[i]),
    ];
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 部件顺序就是事实顺序（哪段话在工具调用前、哪段在结果之后），
        // 换序只能靠删了重加，不提供拖动：能拖的几种换法要么没意义、
        // 要么会把续写挪到工具结果前面。
        //
        // “续答分界”是结构标记而不是内容，不在编辑列表里占一行；
        // 但它仍留在 _parts 里，按真实下标记住，保存时原样写回。
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: visibleParts.length,
          itemBuilder: (context, displayIndex) {
            final entry = visibleParts[displayIndex];
            final index = entry.index;
            final part = entry.part;
            final partKey = _partKeys[index];
            return _PartCard(
              key: ValueKey('part-$partKey-${part.kind}'),
              index: displayIndex,
              part: part,
              controller: part is TextPart
                  ? _controllerFor(partKey, part.text)
                  : null,
              onTextChanged: part is TextPart
                  ? (value) {
                      _parts[index] = TextPart(value);
                      _emit();
                    }
                  : null,
              onDelete: () => unawaited(_remove(index)),
              onExpand: () => unawaited(_expandPart(index)),
            );
          },
        ),
        const SizedBox(height: 8),
        IosCardPress(
          onTap: _addText,
          borderRadius: BorderRadius.circular(12),
          baseColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            l10n.messageEditAddTextPart,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: AppFontWeights.emphasis,
            ),
          ),
        ),
        const SizedBox(height: 8),
        MessageAttachmentEditor(
          parts: _parts,
          onChanged: (parts) {
            _parts = List<MessagePart>.of(parts);
            _syncPartKeys();
            _emit();
            setState(() {});
          },
        ),
      ],
    );
    // 桌面端滚动条收敛：部件列表、正文框内部各自的可滚动区一律不绘制滚动条，
    // 只保留外层弹窗内容区那一条（它才代表“整个编辑内容滚到哪了”）。
    // 滚动能力不受影响——滚轮、拖选、内部自滚行为全部不变。
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: list,
    );
  }
}

class _PartCard extends StatelessWidget {
  const _PartCard({
    super.key,
    required this.index,
    required this.part,
    required this.controller,
    required this.onTextChanged,
    required this.onDelete,
    required this.onExpand,
  });

  final int index;
  final MessagePart part;
  final TextEditingController? controller;
  final ValueChanged<String>? onTextChanged;
  final VoidCallback onDelete;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final label = _partLabel(l10n, part);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 长文本编辑器开关：打开后文本部分改用按行编辑器（短文本仍由它自己回退到原生输入框）。
    final useLongEditor = context
        .watch<SettingsProvider>()
        .useLongMessageEditor;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.appColors.surfaceFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.onSurface.withValues(alpha: isDark ? 0.08 : 0.06),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${index + 1} $label',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                IosIconButton(
                  icon: Lucide.Maximize2,
                  size: 18,
                  color: cs.primary,
                  semanticLabel: l10n.messageEditExpandPart,
                  onTap: onExpand,
                ),
                if (part is! AssistantRoundEndPart)
                  IosIconButton(
                    icon: Lucide.Trash2,
                    size: 18,
                    color: cs.error,
                    semanticLabel: l10n.messageEditDeletePart,
                    onTap: onDelete,
                  ),
              ],
            ),
            if (part is TextPart)
              IosFormTextField(
                label: '',
                controller: controller!,
                hintText: l10n.messageEditTextPart,
                minLines: 3,
                maxLines: _maxPartEditorLines,
                inputFormatters: const [NormalizeNewlinesFormatter()],
                onChanged: onTextChanged,
                outerPadding: EdgeInsets.zero,
                editorBuilder: useLongEditor
                    ? (ctx) => LongMessageEditor(
                        controller: controller!,
                        minLines: 3,
                        maxLines: _maxPartEditorLines,
                        onChanged: onTextChanged,
                        decoration: InputDecoration(
                          isDense: true,
                          isCollapsed: true,
                          hintText: l10n.messageEditTextPart,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        inputFormatters: const [NormalizeNewlinesFormatter()],
                      )
                    : null,
              )
            else
              Text(
                _partSummary(part),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65)),
              ),
          ],
        ),
      ),
    );
  }
}

String _partLabel(AppLocalizations l10n, MessagePart part) => switch (part) {
  TextPart() => l10n.messageEditTextPart,
  ReasoningPart() => l10n.messageEditReasoningPart,
  ToolCallPart() => l10n.messageEditToolCallPart,
  ImagePart() => l10n.messageEditImagePart,
  FilePart() => l10n.messageEditFilePart,
  UnknownPart() => l10n.messageEditUnknownPart,
  MalformedPart() => l10n.messageEditUnknownPart,
  // 一次响应的结束标记是结构信息，不是可编辑内容。
  AssistantRoundEndPart() => l10n.messageEditAssistantRoundEndPart,
  // 账号登录失效的恢复入口不是可编辑内容，按未知部件展示。
  ProviderAuthErrorPart() => l10n.messageEditUnknownPart,
};

/// 只读部件在卡片和大窗口里展示的文本。
String _partSummary(MessagePart part) {
  // 结束标记本身没有可展示的正文。
  if (part is AssistantRoundEndPart) return '';
  if (part is ReasoningPart) return part.text;
  if (part is ToolCallPart) {
    try {
      final value = jsonDecode(part.payloadJson);
      return value is Map ? jsonEncode(value) : part.payloadJson;
    } catch (_) {
      return part.payloadJson;
    }
  }
  if (part is ImagePart) return part.uri;
  if (part is FilePart) return '${part.name}\n${part.uri}';
  return part.encodePayload();
}

/// 打开大窗口编辑或查看单个部件的完整内容。
///
/// [readOnly] 为 true 时只展示（仍可选中复制），不返回新内容。
/// 关闭或取消返回 null；正文部件点保存才返回新文本。
Future<String?> showMessagePartExpandedEditor(
  BuildContext context, {
  required String title,
  required String initialText,
  required bool readOnly,
}) {
  final platform = Theme.of(context).platform;
  final isDesktopPlatform =
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.windows;
  if (isDesktopPlatform) {
    final cs = Theme.of(context).colorScheme;
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: cs.surface,
        shape: DesktopDialogStyle.shape(ctx),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: _ExpandedPartDesktopDialog(
          title: title,
          initialText: initialText,
          readOnly: readOnly,
        ),
      ),
    );
  }
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _ExpandedPartMobileSheet(
      title: title,
      initialText: initialText,
      readOnly: readOnly,
    ),
  );
}

class _ExpandedPartDesktopDialog extends StatefulWidget {
  const _ExpandedPartDesktopDialog({
    required this.title,
    required this.initialText,
    required this.readOnly,
  });

  final String title;
  final String initialText;
  final bool readOnly;

  @override
  State<_ExpandedPartDesktopDialog> createState() =>
      _ExpandedPartDesktopDialogState();
}

class _ExpandedPartDesktopDialogState
    extends State<_ExpandedPartDesktopDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: normalizeNewlines(widget.initialText),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _trimWhitespace() {
    final trimmed = _controller.text.trim();
    if (trimmed == _controller.text) return;
    _controller.value = TextEditingValue(
      text: trimmed,
      selection: TextSelection.collapsed(offset: trimmed.length),
      composing: TextRange.empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: DesktopDialogStyle.editorConstraints(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: AppFontWeights.emphasis,
                      ),
                    ),
                  ),
                  if (!widget.readOnly)
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (context, value, _) => IconButton(
                        tooltip: l10n.messageEditTrimWhitespace,
                        // 首尾已经干净时置灰，避免点了没反应被当成失效。
                        onPressed: value.text.trim() == value.text
                            ? null
                            : _trimWhitespace,
                        icon: Icon(
                          Lucide.Eraser,
                          size: 18,
                          color: cs.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    icon: Icon(
                      Lucide.X,
                      size: 18,
                      color: cs.onSurface.withValues(alpha: 0.75),
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 0.6,
              color: cs.outlineVariant.withValues(alpha: 0.14),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: _ExpandedPartField(
                  controller: _controller,
                  readOnly: widget.readOnly,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text(
                      widget.readOnly
                          ? MaterialLocalizations.of(context).closeButtonLabel
                          : l10n.messageEditCancel,
                    ),
                  ),
                  if (!widget.readOnly) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_controller.text),
                      child: Text(
                        l10n.messageEditExpandedSave,
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: AppFontWeights.semibold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandedPartMobileSheet extends StatefulWidget {
  const _ExpandedPartMobileSheet({
    required this.title,
    required this.initialText,
    required this.readOnly,
  });

  final String title;
  final String initialText;
  final bool readOnly;

  @override
  State<_ExpandedPartMobileSheet> createState() =>
      _ExpandedPartMobileSheetState();
}

class _ExpandedPartMobileSheetState extends State<_ExpandedPartMobileSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: normalizeNewlines(widget.initialText),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _trimWhitespace() {
    final trimmed = _controller.text.trim();
    if (trimmed == _controller.text) return;
    _controller.value = TextEditingValue(
      text: trimmed,
      selection: TextSelection.collapsed(offset: trimmed.length),
      composing: TextRange.empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.96,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, bottom + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: AppFontWeights.emphasis,
                    ),
                  ),
                ),
                if (!widget.readOnly)
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) => IconButton(
                      tooltip: l10n.messageEditTrimWhitespace,
                      // 首尾已经干净时置灰，避免点了没反应被当成失效。
                      onPressed: value.text.trim() == value.text
                          ? null
                          : _trimWhitespace,
                      icon: Icon(
                        Lucide.Eraser,
                        size: 18,
                        color: cs.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(
                    widget.readOnly
                        ? MaterialLocalizations.of(context).closeButtonLabel
                        : l10n.messageEditCancel,
                  ),
                ),
                if (!widget.readOnly)
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_controller.text),
                    child: Text(
                      l10n.messageEditExpandedSave,
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: AppFontWeights.semibold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _ExpandedPartField(
                controller: _controller,
                readOnly: widget.readOnly,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 大窗口里的输入框：铺满可用空间、自身可滚。
class _ExpandedPartField extends StatelessWidget {
  const _ExpandedPartField({required this.controller, required this.readOnly});

  final TextEditingController controller;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final useLongEditor = context
        .watch<SettingsProvider>()
        .useLongMessageEditor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.surfaceFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: useLongEditor
          ? LongMessageEditor(
              controller: controller,
              autofocus: true,
              readOnly: readOnly,
              expands: true,
              minLines: null,
              maxLines: null,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(14, 14, 14, 14),
              ),
            )
          : TextField(
              controller: controller,
              autofocus: true,
              readOnly: readOnly,
              expands: true,
              maxLines: null,
              minLines: null,
              keyboardType: TextInputType.multiline,
              inputFormatters: const [NormalizeNewlinesFormatter()],
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(14, 14, 14, 14),
              ),
            ),
    );
  }
}
