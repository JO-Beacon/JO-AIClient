import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 为 iPad 浮动窗口上方的窗口控制条预留空间。
class FloatingIpadPadding extends StatelessWidget {
  const FloatingIpadPadding({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 只有 iPad 的窗口控制条需要显示器尺寸。Windows 上窗口还原时，
    // 视图到显示器的映射可能取不到，因此这里必须先按平台拦下。
    if (defaultTargetPlatform != TargetPlatform.iOS) return child;

    final mq = MediaQuery.of(context);
    final display = View.of(context).display;
    final displaySize = display.size / display.devicePixelRatio;
    final isFloatingIpad =
        displaySize.shortestSide >= 600 &&
        (mq.size.shortestSide < displaySize.shortestSide - 1 ||
            mq.size.longestSide < displaySize.longestSide - 1);
    final systemTop = mq.viewPadding.top;
    final controlsTop = systemTop < 56 ? 56.0 : systemTop;
    return MediaQuery(
      data: isFloatingIpad
          ? mq.copyWith(
              padding: mq.padding.copyWith(top: controlsTop),
              viewPadding: mq.viewPadding.copyWith(top: controlsTop),
            )
          : mq,
      child: child,
    );
  }
}
