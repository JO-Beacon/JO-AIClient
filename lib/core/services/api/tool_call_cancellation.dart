import 'dart:async';

/// The generation owning a tool call, including work after the HTTP response.
class ToolCallCancellation {
  const ToolCallCancellation({
    required this.isCancelled,
    required this.cancelled,
  });

  final bool Function() isCancelled;
  final Future<void> cancelled;
  static final Object _key = Object();
  static ToolCallCancellation? get current =>
      Zone.current[_key] as ToolCallCancellation?;

  Future<T> run<T>(Future<T> Function() action) {
    throwIfCancelled();
    return runZoned(action, zoneValues: {_key: this});
  }

  /// 覆盖“请求准备”与“供应商续跑”：这两段可能在工具处理之外做 I/O
  /// （例如把工具返回的图片读回来）。
  Stream<T> runStream<T>(Stream<T> Function() action) {
    return Stream<T>.multi((controller) {
      final subscription = runZoned(
        () => action().listen(
          controller.addSync,
          onError: controller.addErrorSync,
          onDone: controller.closeSync,
        ),
        zoneValues: {_key: this},
      );
      controller.onPause = subscription.pause;
      controller.onResume = subscription.resume;
      controller.onCancel = subscription.cancel;
    });
  }

  void throwIfCancelled() {
    if (isCancelled()) throw StateError('tool_call_cancelled');
  }
}
