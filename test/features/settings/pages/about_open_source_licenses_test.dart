import '../../../support/business_test_harness.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/update_provider.dart';
import 'package:Kelivo/desktop/setting/about_pane.dart';
import 'package:Kelivo/features/settings/pages/about_page.dart';
import 'package:Kelivo/features/settings/pages/open_source_licenses_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

/// 随包分发的第三方组件声明必须能从应用内打开，且两端的入口都要有：
/// 缺一边就等于那条分发路径没有声明。
///
/// 这里同时钉住「用的是本应用自己的界面」：Flutter 自带的 `showLicensePage`
/// 是 Material 一套（自带的 AppBar 与 ListTile），与本应用界面语言不一致，
/// 所以两端分别用 [OpenSourceLicensesPage] 与桌面自己的对话框。
void main() {
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'JO-AIClient',
      packageName: 'io.github.jobeacon.joaiclient',
      version: '0.1.17',
      buildNumber: '17',
      buildSignature: '',
    );
  });

  testWidgets('移动端关于页打开的是本应用风格的许可页', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpAboutSurface(tester, const AboutPage());

    final row = find.text('Open source licenses');
    expect(row, findsOneWidget);
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(OpenSourceLicensesPage), findsOneWidget);
    // Material 那套页面不得再出现。
    expect(find.byType(LicensePage), findsNothing);
  });

  testWidgets('桌面端在设置面板内部打开许可页，不弹对话框', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpAboutSurface(tester, const DesktopAboutPane());

    final row = find.text('Open source licenses');
    expect(row, findsOneWidget);
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 在面板内翻页（右半边内全屏），而不是居中对话框。
    expect(find.byType(OpenSourceLicensesPage), findsOneWidget);
    expect(
      tester
          .widget<OpenSourceLicensesPage>(find.byType(OpenSourceLicensesPage))
          .embedded,
      isTrue,
      reason: '桌面端要用嵌入设置面板的形态',
    );
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(LicensePage), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byType(OpenSourceLicensesList),
      findsOneWidget,
      reason: '面板里应由共用的许可列表承载内容',
    );
  });

  testWidgets('空列表按空状态提示渲染，不留下无解释的空白', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: OpenSourceLicensesList(
            groups: const <OpenSourceLicenseGroup>[],
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('No license information was found.'), findsOneWidget);
  });

  testWidgets('点开一条许可会带着该条数据回调', (tester) async {
    OpenSourceLicenseGroup? picked;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => SettingsProvider(createBusinessTestPreferences()),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: OpenSourceLicensesList(
              groups: const <OpenSourceLicenseGroup>[
                OpenSourceLicenseGroup(
                  packageName: 'demo_package',
                  text: 'DEMO LICENSE TEXT',
                ),
              ],
              onSelect: (group) => picked = group,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('demo_package'), findsOneWidget);

    await tester.tap(find.text('demo_package'));
    await tester.pump();

    expect(picked, isNotNull);
    expect(picked!.packageName, 'demo_package');
    expect(picked!.text, 'DEMO LICENSE TEXT');
  });
}

Future<void> _pumpAboutSurface(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<UpdateProvider>.value(
      value: UpdateProvider(),
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AppSnackBarOverlay(child: child),
      ),
    ),
  );
  await tester.pump();
}
