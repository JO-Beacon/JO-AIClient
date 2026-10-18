import 'dart:io';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/provider/widgets/provider_balance_badge.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/business_test_harness.dart';

/// 拦截所有余额请求并计数：本用例只关心“有没有发出去”，不关心响应。
class _CountingHttpOverrides extends HttpOverrides {
  int attempts = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw const HttpException('Balance request intercepted by test');
  }
}

void main() {
  testWidgets('停用的供应商不再自动查询余额', (tester) async {
    const providerKey = 'TestOpenAIProvider';
    final overrides = _CountingHttpOverrides();
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = overrides;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    ProviderBalanceBadge.clearCacheFor(providerKey);
    addTearDown(() => ProviderBalanceBadge.clearCacheFor(providerKey));

    late SettingsProvider settings;
    await tester.runAsync(() async {
      final harness = await createBusinessTestHarness();
      settings = SettingsProvider(harness.preferences);
      await settings.loaded;
    });
    addTearDown(settings.dispose);

    final base = settings.getProviderConfig(
      providerKey,
      defaultName: 'Test OpenAI',
    );
    ProviderConfig configured({
      required bool enabled,
      required String apiKey,
    }) => base.copyWith(
      enabled: enabled,
      balanceEnabled: true,
      apiKey: apiKey,
      baseUrl: 'https://example.invalid/v1',
      balanceApiPath: '/credits',
      balanceResultPath: 'data.total_usage',
    );

    await tester.runAsync(
      () => settings.setProviderConfig(
        providerKey,
        configured(enabled: false, apiKey: 'balance-key'),
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: ProviderBalanceBadge(
              providerKey: providerKey,
              displayName: 'Test OpenAI',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 停用状态下不应发出任何请求，也不显示徽标。
    expect(overrides.attempts, 0);
    expect(find.byType(Icon), findsNothing);

    // 启用后才会查询；请求被拦截，因此显示错误标记。
    await tester.runAsync(
      () => settings.setProviderConfig(
        providerKey,
        configured(enabled: true, apiKey: 'balance-key'),
      ),
    );
    await tester.pumpAndSettle();
    expect(overrides.attempts, 1);
    expect(find.text('!'), findsOneWidget);

    // 再次停用（并改动密钥）后不得重新查询。
    await tester.runAsync(
      () => settings.setProviderConfig(
        providerKey,
        configured(enabled: false, apiKey: 'changed-key'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 1));
    expect(overrides.attempts, 1);
    expect(find.byType(Icon), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
