import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/backup/backup_task_progress.dart';
import 'package:Kelivo/features/backup/widgets/backup_progress_dialog.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

/// 备份/恢复失败时，过去弹窗只说“失败”，用户看不到原因，也无法把原因交给别人。
/// 这里守住两件事：失败时把阶段与具体错误显示出来，并且能一键复制。
void main() {
  late List<String> copied;

  setUp(() {
    copied = <String>[];
  });

  Future<void> pumpLauncher(
    WidgetTester tester, {
    required Future<void> Function(BackupTaskHandle handle) task,
    String Function(Object error)? errorMessage,
  }) async {
    // 默认测试画布比手机矮，错误面板会把按钮挤出可视区。
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showBackupProgressDialog<void>(
                context,
                title: 'Export backup',
                task: task,
                errorMessage: errorMessage,
              ),
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pump();
  }

  testWidgets('失败时显示失败阶段与具体错误', (tester) async {
    await pumpLauncher(
      tester,
      task: (handle) async {
        handle.report(
          BackupProgress(
            phase: BackupPhase.packing,
            processed: 1,
            total: 2,
            cancellable: true,
          ),
        );
        throw StateError('disk_full');
      },
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Operation failed'), findsOneWidget);
    expect(find.textContaining('Failed during'), findsOneWidget);
    expect(find.textContaining('disk_full'), findsOneWidget);
    expect(find.text('Copy error'), findsOneWidget);
    // 失败时不再展示进度条，行动按钮从“取消”换成“关闭”。
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('复制错误会把标题、阶段与错误一起放进剪贴板', (tester) async {
    await pumpLauncher(
      tester,
      task: (handle) async => throw StateError('disk_full'),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Copy error'));
    await tester.pumpAndSettle();

    expect(copied, hasLength(1));
    expect(copied.single, contains('Export backup'));
    expect(copied.single, contains('Failed during'));
    expect(copied.single, contains('disk_full'));
    expect(find.text('Error copied'), findsOneWidget);
  });

  testWidgets('调用方可以给出自己的错误文案', (tester) async {
    await pumpLauncher(
      tester,
      task: (handle) async => throw StateError('raw_internal_detail'),
      errorMessage: (error) => 'Storage is full. Free some space and retry.',
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('Storage is full. Free some space and retry.'),
      findsOneWidget,
    );
    expect(find.textContaining('raw_internal_detail'), findsNothing);
  });

  testWidgets('仍在进行时没有错误面板与复制按钮', (tester) async {
    final pending = Completer<void>();
    await pumpLauncher(tester, task: (handle) => pending.future);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Operation failed'), findsNothing);
    expect(find.text('Copy error'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);

    pending.complete();
    await tester.pumpAndSettle();
  });
}
