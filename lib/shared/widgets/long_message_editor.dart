import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'dart:async';
import '../text_input/message_editing_controller.dart';
import 'app_text_selection_toolbar.dart';
import '../../icons/lucide_adapter.dart';
import '../../l10n/app_localizations.dart';

typedef LongMessageContextMenuBuilder =
    Widget Function(
      BuildContext context,
      TextSelectionToolbarAnchors anchors,
      List<ContextMenuButtonItem> items,
      VoidCallback onDismiss,
      VoidCallback onNativeDismiss,
    );

/// Keeps long message edits local to visible lines instead of reshaping one
/// paragraph containing the whole document after every keystroke.
///
/// JO 改动（三处，升级上游时不要整份覆盖）：
/// 1. `enabled` 开关：关掉时始终用原生输入框（上游总是自行判断）；
/// 2. `inputFormatters`：仅给原生路径，保持我们的换行归一化；
/// 3. `_copyToTextController` 在构建阶段内触发时延到本帧后再写回，
///    否则会撞上“build 中 setState”（面板的全屏编辑弹窗监听了同一个 controller）。
class LongMessageEditor extends StatefulWidget {
  const LongMessageEditor({
    super.key,
    this.inputConnectionFactory,
    this.onInputModeExit,
    required this.controller,
    required this.decoration,
    this.scrollController,
    this.autofocus = false,
    this.focusNode,
    this.style,
    this.cursorColor,
    this.minLines = 8,
    this.maxLines,
    this.expands = false,
    this.readOnly = false,
    this.enabled = true,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onKeyEvent,
    this.textInputAction = TextInputAction.newline,
    this.contentInsertionConfiguration,
    this.contextMenuBuilder,
  });

  final TextEditingController controller;
  final CodeInputConnectionFactory? inputConnectionFactory;

  /// Finish accepted native work before another text input backend is attached.
  final Future<void> Function()? onInputModeExit;
  final InputDecoration decoration;
  final ScrollController? scrollController;
  final bool autofocus;
  final FocusNode? focusNode;
  final TextStyle? style;
  final Color? cursorColor;
  final int? minLines;
  final int? maxLines;
  final bool expands;
  final bool readOnly;

  /// 开关：关掉时始终用原生输入框（保留本仓库原有行为）。
  /// 上游没有这个参数，它总是由阈值与字符守卫自行选择。
  final bool enabled;

  /// 仅对原生输入框生效。按行编辑器不接受 [TextInputFormatter]，
  /// 长文本下的换行归一需在调用方或上游层的镜像逻辑里完成。
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusOnKeyEventCallback? onKeyEvent;
  final TextInputAction textInputAction;
  final ContentInsertionConfiguration? contentInsertionConfiguration;
  final LongMessageContextMenuBuilder? contextMenuBuilder;

  @override
  State<LongMessageEditor> createState() => LongMessageEditorState();
}

class LongMessageEditorState extends State<LongMessageEditor>
    with UndoManagerClient {
  // Leave headroom for the rest of the real home screen at 120 Hz: even a
  // 3,800-character paragraph approached its frame budget on the test phone.
  static const _threshold = 2048;
  // The line editor lays out LTR lines. Keep Flutter's bidi and accessibility
  // editing paths, and preserve documents with non-LF line separators verbatim.
  static final _requiresParagraph = RegExp(
    r'[\r\u0590-\u08ff\u200e-\u200f\u2028-\u202e\u2066-\u2069\ufb1d-\ufdff\ufe70-\ufeff\ud802-\ud803\ud83b]',
  );

  late FocusNode _focus;
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  CodeLineEditingController? _lineController;
  late CodeScrollController _scroll;
  bool _mirroring = false;
  late String _text;
  List<int>? _lineStarts;
  CodeLines? _lastLines;
  bool _long = false;
  bool _composingActive = false;
  bool? _renderingLines;
  // 切换渲染器时保存输入状态，避免新编辑器重新挂载时丢掉焦点和光标。
  bool _modeSwitchHadFocus = false;
  TextSelection? _modeSwitchSelection;
  bool _drainingInput = false;
  bool _inputModeExitReady = false;
  bool _inputModeExitFailed = false;
  bool _refocusAfterModeExit = false;
  MessageEditingController? get _document =>
      widget.controller is MessageEditingController
      ? widget.controller as MessageEditingController
      : null;
  CodeInputConnectionFactory? get _inputFactory =>
      widget.inputConnectionFactory ?? _document?.inputConnectionFactory;
  Future<void> Function()? get _modeExit =>
      widget.onInputModeExit ??
      (_document?.nativeInputEnabled == true ? _document!.handoffInput : null);
  int _inputGeneration = 0;
  bool _documentWasDraining = false;
  bool get _inputPaused =>
      _drainingInput ||
      _inputModeExitFailed ||
      (_document?.isInputPaused ?? false);
  bool get _lineInputActive => _renderingLines == true && !_inputPaused;
  final _undoController = UndoHistoryController();
  BuildContext? _undoContext;
  late final _toolbar = _MessageSelectionToolbarController(
    builder: _buildSelectionToolbar,
  );

  @override
  void initState() {
    super.initState();
    _text = widget.controller.text;
    _focus = widget.focusNode ?? FocusNode();
    _long = _supportsLineEditing(_text);
    _scroll = _makeScrollController();
    widget.controller.addListener(_copyFromTextController);
    _focus.addListener(_onFocusChanged);
    _undoController.addListener(_updatePlatformUndoState);
    _document?.userEdits.addListener(_onDocumentUserEdit);
    _inputGeneration = _document?.inputGeneration ?? 0;
  }

  CodeLineEditingController get _lines => _lineController ??= _createLines();

  CodeLineEditingController _createLines() {
    final lines = CodeLineEditingController(
      options: CodeLineOptions(
        plainText: true,
        inputConnectionFactory: _inputFactory,
      ),
      codeLines: CodeLines.fromText(_text),
      spanBuilder:
          ({
            required context,
            required index,
            required codeLine,
            required textSpan,
            required style,
          }) {
            final composing = _lineController?.composing ?? TextRange.empty;
            if (index == _lineController?.selection.extentIndex &&
                composing.isValid &&
                !composing.isCollapsed &&
                composing.end <= codeLine.text.length) {
              return TextSpan(
                style: _scaledStyle(context),
                children: [
                  TextSpan(text: codeLine.text.substring(0, composing.start)),
                  TextSpan(
                    text: codeLine.text.substring(
                      composing.start,
                      composing.end,
                    ),
                    style: const TextStyle(
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  TextSpan(text: codeLine.text.substring(composing.end)),
                ],
              );
            }
            return TextSpan(
              text: textSpan.text,
              children: textSpan.children,
              style: _scaledStyle(context),
            );
          },
    );
    final current = widget.controller.selection;
    final selection = current.isValid
        ? current
        : TextSelection.collapsed(offset: _text.length);
    final base = _linePosition(selection.baseOffset);
    final extent = _linePosition(selection.extentOffset);
    lines.selection = CodeLineSelection(
      baseIndex: base.index,
      baseOffset: base.offset,
      extentIndex: extent.index,
      extentOffset: extent.offset,
      baseAffinity: selection.affinity,
      extentAffinity: selection.affinity,
    );
    lines.composing = _lineComposing(widget.controller.value);
    _lastLines = lines.codeLines;
    lines.addListener(_copyToTextController);
    return lines;
  }

  // Keep the native document attached through a cut/delete to short text.
  // Retiring it mid-focus can discard the IME's immediately following input.
  bool get _retainNativeEditor =>
      _inputFactory != null && _long && _focus.hasFocus;

  bool _supportsLineEditing(String text) =>
      (text.length >= _threshold || _retainNativeEditor) &&
      !_requiresParagraph.hasMatch(text);

  bool _supportsChangedLines(CodeLines previous, CodeLines next) {
    // Each untouched line is already known to be LTR/LF. The library uses
    // copy-on-write segments, so checking a keystroke need not scan the history.
    // Inserting/removing paragraphs shifts later segment indices. Their line
    // objects remain shared; avoid re-checking the unchanged document suffix.
    final Set<CodeLine>? unchanged = previous.length == next.length
        ? null
        : (Set<CodeLine>.identity()
            ..addAll(previous.segments.expand((segment) => segment.codeLines)));
    for (var index = 0; index < next.segments.length; index++) {
      final lines = next.segments[index].codeLines;
      final old = index < previous.segments.length
          ? previous.segments[index].codeLines
          : null;
      if (identical(lines, old)) continue;
      for (var line = 0; line < lines.length; line++) {
        if (old != null &&
            line < old.length &&
            identical(lines[line], old[line])) {
          continue;
        }
        if (unchanged?.contains(lines[line]) == true) continue;
        if (_requiresParagraph.hasMatch(lines[line].text)) return false;
      }
    }
    return true;
  }

  bool get usesLineEditor => _renderingLines == true;

  TextStyle _scaledStyle(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge!.merge(widget.style);
    return style.copyWith(
      fontSize: MediaQuery.textScalerOf(context).scale(style.fontSize!),
    );
  }

  double get preferredLineHeight {
    final painter = TextPainter(
      text: TextSpan(text: ' ', style: _scaledStyle(context)),
      textDirection: TextDirection.ltr,
    )..layout();
    final height = painter.preferredLineHeight;
    painter.dispose();
    return height;
  }

  void ensureCaretVisible() {
    if (usesLineEditor) _lineController?.makeCursorVisible();
  }

  void hideToolbar() => _toolbar.hide(context);

  CodeScrollController _makeScrollController() => CodeScrollController(
    verticalScroller: widget.scrollController ?? _vertical,
    horizontalScroller: _horizontal,
  );

  @override
  void didUpdateWidget(LongMessageEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _refocusAfterModeExit = false;
      _focus.removeListener(_onFocusChanged);
      if (oldWidget.focusNode == null) _focus.dispose();
      _focus = widget.focusNode ?? FocusNode();
      _focus.addListener(_onFocusChanged);
    }
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller case final MessageEditingController previous) {
        previous.userEdits.removeListener(_onDocumentUserEdit);
      }
      _document?.userEdits.addListener(_onDocumentUserEdit);
      _inputGeneration = _document?.inputGeneration ?? 0;
      _undoController.value = UndoHistoryValue.empty;
      oldWidget.controller.removeListener(_copyFromTextController);
      widget.controller.addListener(_copyFromTextController);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.inputConnectionFactory != widget.inputConnectionFactory) {
      // The factory is captured in CodeLineOptions. A new document/transport
      // needs its own renderer, while accepted old edits stay with their model.
      _retireLineController();
      _drainingInput = false;
      _inputModeExitReady = false;
      _inputModeExitFailed = false;
      _refocusAfterModeExit = false;
      _renderingLines = null;
      _long = false;
      _replaceText(widget.controller.text);
      _long = _supportsLineEditing(_text);
      _documentWasDraining = _document?.isInputPaused ?? false;
    }
    if (oldWidget.scrollController != widget.scrollController) {
      _scroll.dispose();
      _scroll = _makeScrollController();
    }
    if (oldWidget.readOnly != widget.readOnly) _updatePlatformUndoState();
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus && _text.length < _threshold) _long = false;
    if (_focus.hasFocus && !widget.controller.selection.isValid) {
      // Match EditableText's initial focus behavior for an unset selection.
      widget.controller.selection = TextSelection.collapsed(
        offset: _text.length,
      );
    }
    if (mounted) setState(() {});
    _schedulePlatformUndoClient();
  }

  // Both renderers share Flutter's undo coalescing and the same document
  // history. The history widget stays mounted across a size/bidi transition.
  @override
  bool get canUndo =>
      !widget.readOnly &&
      !_inputPaused &&
      (_document?.history?.canUndo ?? _undoController.value.canUndo);

  @override
  bool get canRedo =>
      !widget.readOnly &&
      !_inputPaused &&
      (_document?.history?.canRedo ?? _undoController.value.canRedo);

  @override
  void undo() {
    if (_document?.history != null) {
      if (!widget.readOnly && !_inputPaused) {
        unawaited(_document!.performCommand('undo'));
      }
      return;
    }
    if (!widget.readOnly && !_inputPaused && _undoContext != null) {
      Actions.invoke(
        _undoContext!,
        const UndoTextIntent(SelectionChangedCause.keyboard),
      );
    }
  }

  @override
  void redo() {
    if (_document?.history != null) {
      if (!widget.readOnly && !_inputPaused) {
        unawaited(_document!.performCommand('redo'));
      }
      return;
    }
    if (!widget.readOnly && !_inputPaused && _undoContext != null) {
      Actions.invoke(
        _undoContext!,
        const RedoTextIntent(SelectionChangedCause.keyboard),
      );
    }
  }

  @override
  void handlePlatformUndo(UndoDirection direction) {
    switch (direction) {
      case UndoDirection.undo:
        undo();
      case UndoDirection.redo:
        redo();
    }
  }

  void _updatePlatformUndoState() {
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        UndoManager.client == this) {
      UndoManager.setUndoState(canUndo: canUndo, canRedo: canRedo);
    }
  }

  void _schedulePlatformUndoClient() {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    // EditableText installs its own platform client when mounted/focused.
    // Route native iOS gestures to the persistent history after that happens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_focus.hasFocus) {
        UndoManager.client = this;
        _updatePlatformUndoState();
      } else if (UndoManager.client == this) {
        UndoManager.client = null;
      }
    });
  }

  void _replaceText(String text) {
    if (identical(_text, text)) return;
    _text = text;
    _lineStarts = null;
  }

  List<int> get _starts => _lineStarts ??= () {
    final starts = <int>[0];
    var next = _text.indexOf('\n');
    while (next >= 0) {
      starts.add(next + 1);
      next = _text.indexOf('\n', next + 1);
    }
    return starts;
  }();

  CodeLinePosition _linePosition(int offset) {
    offset = offset.clamp(0, _text.length);
    final starts = _starts;
    var low = 0;
    var high = starts.length;
    while (low + 1 < high) {
      final middle = (low + high) ~/ 2;
      if (starts[middle] <= offset) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return CodeLinePosition(index: low, offset: offset - starts[low]);
  }

  int _textOffset(CodeLinePosition position) =>
      _starts[position.index] + position.offset;

  TextRange _lineComposing(TextEditingValue value) {
    if (!value.composing.isValid) return TextRange.empty;
    final start = _linePosition(value.composing.start);
    final end = _linePosition(value.composing.end);
    return start.index == end.index
        ? TextRange(start: start.offset, end: end.offset)
        : TextRange.empty;
  }

  void _onDocumentUserEdit() {
    widget.onChanged?.call(widget.controller.text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ensureCaretVisible();
    });
  }

  void _copyFromTextController() {
    if (_mirroring) return;
    final generation = _document?.inputGeneration ?? 0;
    final draining = _document?.isInputPaused ?? false;
    if (_inputGeneration != generation || _documentWasDraining != draining) {
      _inputGeneration = generation;
      _documentWasDraining = draining;
      if (mounted) setState(() {});
    }
    final value = widget.controller.value;
    final textChanged = !identical(_text, value.text);
    _replaceText(value.text);
    // 输入法正在组合的中间产物不能参与 2048 判断，也不能在组合期间切换
    // 编辑器，否则拼音、假名等尚未上屏的内容会被切换打断。
    final composing = value.composing;
    final composingActive = composing.isValid && !composing.isCollapsed;
    final composingChanged = composingActive != _composingActive;
    _composingActive = composingActive;
    final committedText = composingActive
        ? value.text.replaceRange(composing.start, composing.end, '')
        : value.text;
    final nextLong = (textChanged || composingChanged)
        ? (composingActive ? _long : _supportsLineEditing(committedText))
        : _long;
    final changedMode = _long != nextLong;
    _long = nextLong;
    if (changedMode && _focus.hasFocus) {
      _modeSwitchHadFocus = true;
      _modeSwitchSelection = value.selection;
    }
    if (_lineController == null) {
      if (changedMode && mounted) setState(() {});
      return;
    }
    if (textChanged && !nextLong && _inputFactory != null) {
      // Keep the raw model intact while transferring to the paragraph editor.
      // Its CRLF/bidi/accessibility path must not receive a normalized line
      // controller echo before the old input client detaches.
      if (changedMode && mounted) setState(() {});
      return;
    }
    _mirroring = true;
    try {
      final selection = value.selection.isValid
          ? value.selection
          : TextSelection.collapsed(offset: value.text.length);
      if (!value.selection.isValid && _focus.hasFocus) {
        widget.controller.selection = selection;
      }
      if (textChanged && nextLong && _inputFactory != null) {
        // Use the same incremental document update as native edits. Rebuilding
        // every CodeLine loses shared unchanged lines and the document cache.
        _lines.editDocument(
          value.copyWith(selection: selection),
          revealCaret: false,
        );
      } else {
        final base = _linePosition(selection.baseOffset);
        final extent = _linePosition(selection.extentOffset);
        _lines.value = CodeLineEditingValue(
          codeLines: textChanged
              ? CodeLines.fromText(value.text)
              : _lines.codeLines,
          selection: CodeLineSelection(
            baseIndex: base.index,
            baseOffset: base.offset,
            extentIndex: extent.index,
            extentOffset: extent.offset,
            baseAffinity: selection.affinity,
            extentAffinity: selection.affinity,
          ),
          composing: _lineComposing(value),
        );
      }
      _lastLines = _lines.codeLines;
    } finally {
      _mirroring = false;
    }
    if (changedMode && mounted) setState(() {});
  }

  void _copyToTextController() {
    // 构建阶段内部组件（如 CodeEditor 初始化）可能触发一次镜像；此时直接写回
    // controller 会撞上“build 中 setState”。把它推到本帧之后。
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _copyToTextController();
      });
      return;
    }
    if (_mirroring || (_inputFactory != null && !_lineInputActive)) return;
    var textChanged = false;
    var nextLong = _long;
    _mirroring = true;
    try {
      if (!identical(_lastLines, _lines.codeLines)) {
        final previous = _lastLines;
        final nextText = _lines.text;
        textChanged = _text != nextText;
        _replaceText(nextText);
        nextLong =
            (_text.length >= _threshold || _retainNativeEditor) &&
            (_long && previous != null
                ? _supportsChangedLines(previous, _lines.codeLines)
                : !_requiresParagraph.hasMatch(_text));
        _lastLines = _lines.codeLines;
      }
      final selection = _lines.selection;
      final composing = _lines.composing;
      widget.controller.value = TextEditingValue(
        text: _text,
        composing: composing.isValid
            ? TextRange(
                start: _textOffset(
                  CodeLinePosition(
                    index: selection.extentIndex,
                    offset: composing.start,
                  ),
                ),
                end: _textOffset(
                  CodeLinePosition(
                    index: selection.extentIndex,
                    offset: composing.end,
                  ),
                ),
              )
            : TextRange.empty,
        selection: TextSelection(
          baseOffset: _textOffset(
            CodeLinePosition(
              index: selection.baseIndex,
              offset: selection.baseOffset,
            ),
          ),
          extentOffset: _textOffset(
            CodeLinePosition(
              index: selection.extentIndex,
              offset: selection.extentOffset,
            ),
          ),
          affinity: selection.extentAffinity,
        ),
      );
    } finally {
      _mirroring = false;
    }
    if (_long != nextLong && mounted) setState(() => _long = nextLong);
    if (textChanged) widget.onChanged?.call(_text);
  }

  @override
  void dispose() {
    _toolbar.hide(context);
    if (UndoManager.client == this) UndoManager.client = null;
    _undoController.dispose();
    _document?.userEdits.removeListener(_onDocumentUserEdit);
    widget.controller.removeListener(_copyFromTextController);
    _lineController?.removeListener(_copyToTextController);
    _lineController?.dispose();
    _scroll.dispose();
    _vertical.dispose();
    _horizontal.dispose();
    _focus.removeListener(_onFocusChanged);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_document?.history != null) {
      return Actions(
        actions: {
          UndoTextIntent: CallbackAction<UndoTextIntent>(
            onInvoke: (_) => undo(),
          ),
          RedoTextIntent: CallbackAction<RedoTextIntent>(
            onInvoke: (_) => redo(),
          ),
        },
        child: _buildEditor(context),
      );
    }
    return UndoHistory<TextEditingValue>(
      key: ValueKey(widget.controller),
      value: widget.controller,
      focusNode: _focus,
      controller: _undoController,
      shouldChangeUndoStack: (previous, next) {
        if (!next.selection.isValid) return false;
        if (previous == null) return true;
        if (defaultTargetPlatform != TargetPlatform.android &&
            !next.composing.isCollapsed) {
          return false;
        }
        return previous.text != next.text ||
            previous.composing != next.composing;
      },
      undoStackModifier: (value) => value.copyWith(composing: TextRange.empty),
      onTriggered: (value) {
        final changed = widget.controller.text != value.text;
        widget.controller.value = value;
        if (changed) widget.onChanged?.call(value.text);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ensureCaretVisible();
        });
      },
      child: Builder(
        builder: (context) {
          _undoContext = context;
          return Actions(
            actions: {
              UndoTextIntent: CallbackAction<UndoTextIntent>(
                onInvoke: (_) => undo(),
              ),
              RedoTextIntent: CallbackAction<RedoTextIntent>(
                onInvoke: (_) => redo(),
              ),
            },
            child: _buildEditor(context),
          );
        },
      ),
    );
  }

  Widget _buildSelectionToolbar({
    required BuildContext context,
    required TextSelectionToolbarAnchors anchors,
    required CodeLineEditingController controller,
    required VoidCallback onDismiss,
    required VoidCallback onRefresh,
  }) {
    final owner = _lineController;
    bool active() =>
        mounted && _lineInputActive && identical(owner, _lineController);
    final selected = !controller.selection.isCollapsed;
    final items = <ContextMenuButtonItem>[
      if (selected && !widget.readOnly)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.cut,
          onPressed: () {
            if (!active() || widget.readOnly) return;
            controller.cut();
            onDismiss();
          },
        ),
      if (selected)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () {
            if (!active()) return;
            controller.copy();
            onDismiss();
          },
        ),
      if (!widget.readOnly)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: () {
            if (!active() || widget.readOnly) return;
            if (_document?.nativeInputEnabled == true) {
              unawaited(_document!.performCommand('paste'));
            } else {
              controller.paste();
            }
            onDismiss();
          },
        ),
      ContextMenuButtonItem(
        type: ContextMenuButtonType.selectAll,
        onPressed: () {
          if (!active()) return;
          controller.selectAll();
          onRefresh();
        },
      ),
    ];
    return widget.contextMenuBuilder?.call(
          context,
          anchors,
          items,
          onDismiss,
          onDismiss,
        ) ??
        AppTextSelectionToolbar(
          anchors: anchors,
          buttonItems: items,
          selectionContext: context,
          onDismiss: onDismiss,
        );
  }

  void _retireInputForModeChange() {
    if (_drainingInput || _inputModeExitFailed) return;
    _drainingInput = true;
    final controller = widget.controller;
    final exit = _modeExit!;
    // This build first makes the old editor read-only and detaches its IME
    // handle. Only after all accepted work is delivered can TextField open.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !identical(controller, widget.controller)) return;
      _toolbar.hide(context);
      _updatePlatformUndoState();
      // A new EditableText reusing an already focused node may never receive
      // a focus notification and therefore never attach its native input.
      // Release the old attachment's focus, then restore it after handoff if
      // the user has not focused another control in the meantime.
      _refocusAfterModeExit = _focus.hasFocus;
      if (_refocusAfterModeExit) _focus.unfocus();
      try {
        await exit();
      } catch (error, stack) {
        if (mounted && identical(controller, widget.controller)) {
          setState(() => _inputModeExitFailed = true);
        }
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            context: ErrorDescription(
              'while completing the native editor handoff',
            ),
          ),
        );
        return;
      }
      if (!mounted || !identical(controller, widget.controller)) return;
      setState(() {
        _drainingInput = false;
        _inputModeExitReady = true;
      });
    });
  }

  void _retireLineController() {
    final retired = _lineController;
    retired?.removeListener(_copyToTextController);
    _lineController = null;
    _lastLines = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => retired?.dispose());
  }

  /// 新挂载的原生输入框不会收到焦点变化，光标闪烁计时器没有启动，
  /// 光标颜色透明度会一直停在 0。这里用一次不改变位置的选区更新唤醒它。
  void _wakeNativeCaret() {
    final selection = widget.controller.selection;
    if (!selection.isValid) return;
    final toggled = selection.copyWith(
      affinity: selection.affinity == TextAffinity.downstream
          ? TextAffinity.upstream
          : TextAffinity.downstream,
    );
    widget.controller.selection = toggled;
    widget.controller.selection = selection;
  }

  /// 让新挂载的编辑器显式打开文字输入连接。
  ///
  /// 新旧编辑器共用同一个 FocusNode。新编辑器初始化时焦点已经存在，
  /// EditableText 不会再收到焦点变化通知，于是可能只有按键事件、没有输入法连接：
  /// 退格能删，却打不出字。这里找到它并主动请求键盘。
  void _requestActiveEditorKeyboard() {
    EditableTextState? target;
    void visit(Element element) {
      if (target != null) return;
      if (element is StatefulElement) {
        final state = element.state;
        if (state is EditableTextState) {
          target = state;
          return;
        }
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    final editable = target;
    if (editable == null) return;
    editable.requestKeyboard();
    if (_renderingLines != true) {
      // 新挂载的原生输入框滚动位置默认在顶部。把光标所在位置重新带入视口，
      // 否则从按行编辑器删回阈值以下时画面会跳回开头。
      final selection = widget.controller.selection;
      if (selection.isValid) {
        editable.bringIntoView(TextPosition(offset: selection.extentOffset));
      }
    }
  }

  Widget _buildEditor(BuildContext context) {
    final lineEditorPermitted =
        widget.enabled &&
        !MediaQuery.accessibleNavigationOf(context) &&
        Directionality.of(context) != TextDirection.rtl;
    var renderingLines = lineEditorPermitted && _long;
    if (!renderingLines &&
        _renderingLines == true &&
        _modeExit != null &&
        !_inputModeExitReady) {
      renderingLines = true;
      _retireInputForModeChange();
    } else {
      _inputModeExitReady = false;
    }
    final switching =
        _renderingLines != null && _renderingLines != renderingLines;
    final restoreFocusAfterSwitch =
        switching && (_focus.hasFocus || _modeSwitchHadFocus);
    if (restoreFocusAfterSwitch || (_refocusAfterModeExit && !_drainingInput)) {
      _refocusAfterModeExit = false;
      final controller = widget.controller;
      final focus = _focus;
      final selection = _modeSwitchSelection;
      // 原生输入交接的选区以交接后的文档为准，不能拿切换前的旧位置覆盖。
      final allowNativeSelectionRestore =
          _inputFactory == null && !_drainingInput;
      _modeSwitchHadFocus = false;
      _modeSwitchSelection = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _inputPaused ||
            !identical(controller, widget.controller) ||
            !identical(focus, _focus)) {
          return;
        }
        final primary = FocusManager.instance.primaryFocus;
        if (_focus.hasFocus || primary == null || primary is FocusScopeNode) {
          _focus.requestFocus();
          if (_renderingLines == true) {
            final lines = _lineController;
            if (lines != null && selection != null && selection.isValid) {
              final base = _linePosition(selection.baseOffset);
              final extent = _linePosition(selection.extentOffset);
              lines.selection = CodeLineSelection(
                baseIndex: base.index,
                baseOffset: base.offset,
                extentIndex: extent.index,
                extentOffset: extent.offset,
                baseAffinity: selection.affinity,
                extentAffinity: selection.affinity,
              );
            }
            _lineController?.makeCursorVisible();
          } else if (allowNativeSelectionRestore &&
              selection != null &&
              selection.isValid) {
            controller.selection = selection;
          }
          _requestActiveEditorKeyboard();
          if (_renderingLines != true && _focus.hasFocus) {
            _wakeNativeCaret();
          }
        }
      });
    }
    if (_renderingLines != renderingLines) _schedulePlatformUndoClient();
    if (_renderingLines == true && !renderingLines && _inputFactory != null) {
      // Clipboard reads belong to the renderer that initiated them. Retire
      // its controller after unmount so late replies cannot overwrite the new
      // paragraph editor, or a later line editor created from its final model.
      _retireLineController();
    }
    _renderingLines = renderingLines;
    if (!renderingLines) {
      return RepaintBoundary(
        child: TextField(
          controller: widget.controller,
          focusNode: _focus,
          scrollController: widget.scrollController,
          autofocus: widget.autofocus,
          keyboardType: TextInputType.multiline,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          expands: widget.expands,
          readOnly: widget.readOnly || _inputPaused,
          inputFormatters: widget.inputFormatters,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          style: widget.style,
          cursorColor: widget.cursorColor,
          textInputAction: widget.textInputAction,
          contentInsertionConfiguration: widget.contentInsertionConfiguration,
          contextMenuBuilder: (context, state) {
            final items = state.contextMenuButtonItems.map((item) {
              if (item.type != ContextMenuButtonType.paste ||
                  _document?.nativeInputEnabled != true) {
                return item;
              }
              return ContextMenuButtonItem(
                type: item.type,
                label: item.label,
                onPressed: () {
                  if (_inputPaused || widget.readOnly) return;
                  unawaited(_document!.performCommand('paste'));
                  state.hideToolbar();
                },
              );
            }).toList();
            return widget.contextMenuBuilder?.call(
                  context,
                  state.contextMenuAnchors,
                  items,
                  state.hideToolbar,
                  () => state.hideToolbar(false),
                ) ??
                AppTextSelectionToolbar(
                  anchors: state.contextMenuAnchors,
                  buttonItems: items,
                  selectionContext: state.context,
                  onDismiss: () => state.hideToolbar(false),
                );
          },
          decoration: widget.decoration,
        ),
      );
    }
    final theme = Theme.of(context);
    final style = _scaledStyle(context);
    final editor = NotificationListener<ScrollNotification>(
      // An editor's internal scrolling must not tint the surrounding AppBar.
      onNotification: (_) => true,
      child: InputDecorator(
        decoration: widget.decoration,
        isFocused: _focus.hasFocus,
        child: RepaintBoundary(
          child: CodeEditor(
            key: ValueKey((_lines, _inputGeneration)),
            controller: _lines,
            focusNode: _focus,
            autofocus: widget.autofocus,
            readOnly: widget.readOnly || _inputPaused,
            showCursorWhenReadOnly: false,
            onSubmitted: widget.onSubmitted,
            onKeyEvent: (node, event) => _inputPaused
                ? KeyEventResult.handled
                : widget.onKeyEvent?.call(node, event) ??
                      KeyEventResult.ignored,
            textInputAction: widget.textInputAction,
            contentInsertionConfiguration: widget.contentInsertionConfiguration,
            scrollController: _scroll,
            wordWrap: true,
            autocompleteSymbols: false,
            shortcutsActivatorsBuilder: const _PlainMessageShortcuts(),
            chunkAnalyzer: const NonCodeChunkAnalyzer(),
            maxLengthSingleLineRendering: 1 << 30,
            padding: EdgeInsets.zero,
            margin: EdgeInsets.zero,
            scrollbarBuilder: (_, child, _) => child,
            style: CodeEditorStyle(
              fontSize: style.fontSize,
              fontFamily: style.fontFamily,
              fontFamilyFallback: style.fontFamilyFallback,
              fontHeight: style.height,
              textColor: style.color,
              cursorColor: widget.cursorColor ?? theme.colorScheme.primary,
              selectionColor: theme.textSelectionTheme.selectionColor,
              cursorLineColor: Colors.transparent,
            ),
            toolbarController: _toolbar,
          ),
        ),
      ),
    );
    // 常驻标记：只在按行编辑真正接管时出现，低透明度、不可点击，
    // 让用户知道当前用的是哪套编辑器，又不遮挡操作。
    Widget content = editor;
    if (_renderingLines == true) {
      final indicatorLabel = AppLocalizations.of(
        context,
      )?.longMessageEditorActiveIndicator;
      content = Stack(
        children: [
          editor,
          Positioned(
            top: 6,
            right: 8,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.4,
                child: Icon(
                  Lucide.Type,
                  size: 14,
                  color: theme.colorScheme.onSurface,
                  semanticLabel: indicatorLabel,
                ),
              ),
            ),
          ),
        ],
      );
    }
    // Keep the editor mounted when the composer expands or collapses, retaining
    // its native input connection, selection and render-controller bindings.
    return IgnorePointer(
      ignoring: _inputPaused,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: widget.maxLines == null
              ? double.infinity
              : preferredLineHeight * widget.maxLines! +
                    (widget.decoration.contentPadding?.vertical ?? 0),
        ),
        child: content,
      ),
    );
  }
}

class _PlainMessageShortcuts extends DefaultCodeShortcutsActivatorsBuilder {
  const _PlainMessageShortcuts();

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) => switch (type) {
    CodeShortcutType.undo ||
    CodeShortcutType.redo ||
    CodeShortcutType.indent ||
    CodeShortcutType.outdent ||
    CodeShortcutType.lineMoveUp ||
    CodeShortcutType.lineMoveDown ||
    CodeShortcutType.singleLineComment ||
    CodeShortcutType.multiLineComment => const [],
    _ => super.build(type),
  };
}

// Mobile anchors follow the render layer; desktop secondary-click anchors are
// already in screen coordinates and have no renderRect.
class _MessageSelectionToolbarController implements SelectionToolbarController {
  _MessageSelectionToolbarController({required this.builder});

  final ToolbarMenuBuilder builder;
  final _desktop = ContextMenuController();
  late final _mobile = MobileSelectionToolbarController(builder: builder);

  @override
  void hide(BuildContext context) {
    _desktop.remove();
    _mobile.hide(context);
  }

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    hide(context);
    if (renderRect != null) {
      _mobile.show(
        context: context,
        controller: controller,
        anchors: anchors,
        renderRect: renderRect,
        layerLink: layerLink,
        visibility: visibility,
      );
      return;
    }
    _desktop.show(
      context: context,
      contextMenuBuilder: (_) => CodeEditorTapRegion(
        child: builder(
          context: context,
          anchors: anchors,
          controller: controller,
          onDismiss: () => hide(context),
          onRefresh: () => show(
            context: context,
            controller: controller,
            anchors: anchors,
            layerLink: layerLink,
            visibility: visibility,
          ),
        ),
      ),
    );
  }
}
