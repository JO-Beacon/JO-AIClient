import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/search/search_service.dart';
import 'package:Kelivo/desktop/setting/search_services_pane.dart';
import 'package:Kelivo/icons/lucide_adapter.dart' as lucide;
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/theme/theme_factory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/business_test_harness.dart';

/// 桌面端的搜索供应商设置自成一套对话框。新增 Exa MCP 后，
/// 这里守住“能加、能改”：它不需要密钥，地址留空就用默认入口，
/// 改的时候不能把已经填好的附加密钥弄丢。
Future<SettingsProvider> _pumpPane(
  WidgetTester tester, {
  List<SearchServiceOptions>? services,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final settings = SettingsProvider(createBusinessTestPreferences());
  addTearDown(settings.dispose);
  await settings.loaded;
  if (services != null) {
    await settings.setSearchServices(services);
  }

  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: MaterialApp(
        theme: buildLightTheme(null),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: DesktopSearchServicesPane()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return settings;
}

Future<void> _selectServiceType(WidgetTester tester, String label) async {
  // 弹窗里的类型选择器（面板卡片上也会出现同一个名字，取后面的那个）。
  await tester.tap(find.text('Bing (Local)').last);
  await tester.pumpAndSettle();
  final option = find.text(label);
  await tester.dragUntilVisible(
    option,
    find.byType(SingleChildScrollView).last,
    const Offset(0, -80),
  );
  await tester.tap(option.last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('桌面端可以添加不需要密钥的 Exa MCP 服务', (tester) async {
    final settings = await _pumpPane(tester);

    // 面板顶部工具栏的“添加”按钮（同一个图标在下面还有其它用途）。
    await tester.tap(find.byIcon(lucide.Lucide.Plus).first);
    await tester.pumpAndSettle();
    await _selectServiceType(tester, 'Exa MCP');

    expect(find.text('API Key (optional)'), findsOneWidget);
    expect(find.text(ExaMcpOptions.defaultUrl), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    final saved = settings.searchServices.last;
    expect(saved, isA<ExaMcpOptions>());
    final mcp = saved as ExaMcpOptions;
    expect(mcp.apiKey, isEmpty);
    expect(mcp.resolvedUrl, ExaMcpOptions.defaultUrl);
  });

  testWidgets('桌面端编辑 Exa MCP 时保留附加密钥与自定义入口', (tester) async {
    final settings = await _pumpPane(
      tester,
      services: [
        ExaMcpOptions(
          id: 'exa-mcp',
          apiKey: 'primary',
          url: 'https://old.example.com/mcp',
          extraApiKeys: const ['extra'],
        ),
      ],
    );

    await tester.tap(find.byIcon(lucide.Lucide.Settings2));
    await tester.pumpAndSettle();

    final urlField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == ExaMcpOptions.defaultUrl,
    );
    await tester.enterText(urlField, ' https://example.com/mcp ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = settings.searchServices.single;
    expect(saved, isA<ExaMcpOptions>());
    final mcp = saved as ExaMcpOptions;
    expect(mcp.id, 'exa-mcp');
    expect(mcp.apiKey, 'primary');
    expect(mcp.extraApiKeys, ['extra']);
    expect(mcp.resolvedUrl, 'https://example.com/mcp');
  });

  testWidgets('读网页模式下拉框显示每项副标题', (tester) async {
    await _pumpPane(
      tester,
      services: [TavilyOptions(id: 'tavily', apiKey: 'k')],
    );

    final trigger = find.byKey(const ValueKey('desktop-web-fetch-mode'));
    await tester.dragUntilVisible(
      trigger,
      find.byType(CustomScrollView),
      const Offset(0, -120),
    );
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    // 跟随意项把当前目标写进标题，其余选项用副标题解释含义。
    expect(
      find.text('Free. This device requests the page directly.'),
      findsOneWidget,
    );
    expect(find.text('Search only, without reading pages'), findsOneWidget);
    expect(find.text('Uses this service\'s API key and quota'), findsOneWidget);
  });

  testWidgets('桌面端可以添加 DeepSeek 并保存密钥', (tester) async {
    final settings = await _pumpPane(tester);

    await tester.tap(find.byIcon(lucide.Lucide.Plus).first);
    await tester.pumpAndSettle();
    await _selectServiceType(tester, 'DeepSeek');

    expect(find.text('API Key'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'deepseek-key');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    final saved = settings.searchServices.last;
    expect(saved, isA<DeepSeekOptions>());
    expect((saved as DeepSeekOptions).apiKey, 'deepseek-key');
  });

  testWidgets('桌面端编辑 DeepSeek 时保留附加密钥', (tester) async {
    final settings = await _pumpPane(
      tester,
      services: [
        DeepSeekOptions(
          id: 'deepseek',
          apiKey: 'old-key',
          extraApiKeys: const ['extra-key'],
        ),
      ],
    );

    await tester.tap(find.byIcon(lucide.Lucide.Settings2));
    await tester.pumpAndSettle();

    expect(find.text('old-key'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'new-key');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = settings.searchServices.single as DeepSeekOptions;
    expect(saved.id, 'deepseek');
    expect(saved.apiKey, 'new-key');
    expect(saved.extraApiKeys, ['extra-key']);
  });
}
