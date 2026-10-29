import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../../core/models/progress_update.dart';
import '../../core/services/backup/backup_cancel_token.dart';
import '../../core/services/backup/backup_progress_timeline.dart';
import '../../core/services/backup/backup_task_progress.dart';
import '../widgets/loading_dialog_card.dart';

/// 只有在不可关闭的加载对话框绘制完成后才运行 [task]。
Future<T> runWithLoadingTaskDialog<T>({
  required BuildContext context,
  Future<T> Function(ProgressCallback onProgress)? task,
  Future<T> Function(ProgressCallback onProgress, BackupCancelToken token)?
  cancellableTask,
  String? label,
  String? cancelLabel,
  BackupProgressFlow? flow,
  String Function(BackupPhase phase)? phaseLabelBuilder,
}) async {
  assert(task != null || cancellableTask != null);
  final navigator = Navigator.of(context, rootNavigator: true);
  final progress = ValueNotifier<ProgressUpdate?>(null);
  // 有 flow 时把“阶段内进度”换算成整条流水线的总体进度，否则沿用原始比值。
  final timeline = flow == null ? null : BackupProgressTimeline(flow);
  final cancelToken = BackupCancelToken();
  // 用普通路由承载加载层，而不是直接塞进 Overlay。这样任务进行中弹出的
  // 密码框等路由会排在加载层之上，不会被全屏 ModalBarrier 挡住输入。
  final route = PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: false,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, _, _) {
      final loadingLayer = Stack(
        fit: StackFit.expand,
        children: [
          const ModalBarrier(dismissible: false, color: Colors.black54),
          ValueListenableBuilder<ProgressUpdate?>(
            valueListenable: progress,
            builder: (context, update, child) {
              final phase = update?.phase;
              final fraction = timeline == null
                  ? update?.fraction
                  : timeline.updatePhase(phase, update?.fraction);
              return LoadingDialogCard(
                label: label,
                progress: fraction,
                phaseLabel: (phase != null && phaseLabelBuilder != null)
                    ? phaseLabelBuilder(phase)
                    : null,
                onCancel: cancellableTask == null ? null : cancelToken.cancel,
                cancelLabel: cancelLabel,
              );
            },
          ),
        ],
      );
      return PopScope(
        canPop: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (defaultTargetPlatform == TargetPlatform.windows)
              Positioned.fill(top: 40, child: loadingLayer)
            else
              loadingLayer,
          ],
        ),
      );
    },
  );
  navigator.push(route);

  // 路由的插入及其首次绘制发生在下一帧。如果在此之前开始同步前缀操作，
  // 窗口可能会保持视觉空白。
  await WidgetsBinding.instance.endOfFrame;

  try {
    if (cancellableTask != null) {
      return await cancellableTask(
        (update) => progress.value = update,
        cancelToken,
      );
    }
    final regularTask = task;
    if (regularTask == null) {
      throw StateError('missing_loading_task');
    }
    return await regularTask((update) => progress.value = update);
  } finally {
    if (route.isActive) navigator.removeRoute(route);
    cancelToken.dispose();
    progress.dispose();
  }
}
