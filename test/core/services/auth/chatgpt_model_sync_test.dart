import 'dart:convert';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/auth/provider_oauth_adapter.dart';
import 'package:Kelivo/core/services/auth/provider_oauth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../support/business_test_harness.dart';

/// 供应商的模型列表会随**客户端版本**变化（新模型只对够新的客户端可见）。
/// 所以启动时要检查：上次拉取时用的版本和现在不一致就重拉一次；
/// 拉不到就保留已保存的列表，等下次启动或手动同步再试。
ProviderConfig _account({
  String id = 'account',
  String? version,
  bool enabled = true,
  OAuthProvider provider = OAuthProvider.chatgpt,
  bool signedIn = true,
}) => ProviderConfig(
  id: id,
  enabled: enabled,
  name: provider.displayName,
  apiKey: '',
  baseUrl: provider.baseUrl,
  oauthProvider: provider,
  oauthCredentials: signedIn
      ? ProviderOAuthCredentials(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          sessionId: 'session',
          accountId: id,
        )
      : null,
  models: const ['gpt-6-sol'],
  modelOverrides: const {
    'gpt-6-sol': {'temperature': .7},
  },
  oauthModelsSyncedAt: DateTime.utc(2026, 9, 1),
  oauthModelsClientVersion: version,
);

http.Response _catalog() => http.Response(
  jsonEncode({
    'models': [
      {'slug': 'gpt-6-sol'},
      {'slug': 'gpt-6.1-sol', 'supported_in_api': false},
    ],
  }),
  200,
);

Future<SettingsProvider> _loadAccounts(List<ProviderConfig> accounts) async {
  final harness = await createBusinessTestHarness(
    initial: {
      'provider_configs_v1': jsonEncode({
        for (final config in accounts) config.id: config.toJson(),
      }),
    },
  );
  final settings = SettingsProvider(harness.preferences);
  addTearDown(settings.dispose);
  return settings;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final previous in [null, '0.153.0']) {
    test('上次同步版本为 $previous 时，启动会重拉并记下新版本', () async {
      final settings = await _loadAccounts([_account(version: previous)]);
      final versions = <String?>[];
      final service = ProviderOAuthService(
        clientFactory: (_) => MockClient((request) async {
          expect(request.url.path, '/backend-api/codex/models');
          versions.add(request.url.queryParameters['client_version']);
          expect(request.headers['version'], codexClientVersion);
          expect(request.headers['chatgpt-account-id'], 'account');
          return _catalog();
        }),
      )..bind(settings);

      await service.syncOutdatedModels(settings);

      expect(versions, [codexClientVersion]);
      final saved = settings.providerConfigs['account']!;
      expect(saved.models, containsAll(['gpt-6-sol', 'gpt-6.1-sol']));
      expect(
        saved.modelOverrides['gpt-6-sol']['temperature'],
        .7,
        reason: '用户自己改过的设置不能被同步覆盖掉',
      );
      expect(saved.oauthModelsClientVersion, codexClientVersion);
      expect(
        saved.oauthModelsSyncedAt!.isAfter(DateTime.utc(2026, 9, 1)),
        isTrue,
      );
    });
  }

  test('版本没变时不再重复请求', () async {
    final settings = await _loadAccounts([
      _account(version: codexClientVersion),
    ]);
    var calls = 0;
    final service = ProviderOAuthService(
      clientFactory: (_) => MockClient((request) async {
        calls++;
        return _catalog();
      }),
    )..bind(settings);

    await service.syncOutdatedModels(settings);

    expect(calls, 0);
  });

  test('重拉失败时不写版本，已保存的模型列表保持原样', () async {
    final settings = await _loadAccounts([_account(version: null)]);
    final service = ProviderOAuthService(
      clientFactory: (_) => MockClient((request) async {
        return http.Response('nope', 500);
      }),
    )..bind(settings);

    await service.syncOutdatedModels(settings);

    final saved = settings.providerConfigs['account']!;
    expect(saved.oauthModelsClientVersion, isNull, reason: '失败要留给下次重试');
    expect(saved.models, ['gpt-6-sol']);
    expect(saved.oauthModelsSyncedAt, DateTime.utc(2026, 9, 1));
  });

  test('停用、未登录或不是该供应商的账号都不会被同步', () async {
    final settings = await _loadAccounts([
      _account(id: 'disabled', version: null, enabled: false),
      _account(id: 'signed-out', version: null, signedIn: false),
      _account(id: 'grok', version: null, provider: OAuthProvider.grok),
    ]);
    var calls = 0;
    final service = ProviderOAuthService(
      clientFactory: (_) => MockClient((request) async {
        calls++;
        return _catalog();
      }),
    )..bind(settings);

    await service.syncOutdatedModels(settings);

    expect(calls, 0);
  });

  test('登录写回凭证时清掉旧版本，之后会重新拉一次', () async {
    final settings = await _loadAccounts([
      _account(version: codexClientVersion),
    ]);
    await settings.loaded;

    // 重新登录等同于换了会话：模型列表要重新认识一次。
    await settings.setProviderConfig(
      'account',
      settings.providerConfigs['account']!.copyWith(
        oauthCredentials: ProviderOAuthCredentials(
          accessToken: 'other',
          refreshToken: 'other',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          sessionId: 'other-session',
          accountId: 'account',
        ),
        oauthModelsClientVersion: null,
      ),
    );

    var calls = 0;
    final refreshed = ProviderOAuthService(
      clientFactory: (_) => MockClient((request) async {
        calls++;
        return _catalog();
      }),
    )..bind(settings);
    await refreshed.syncOutdatedModels(settings);

    expect(calls, 1);
    expect(
      settings.providerConfigs['account']!.oauthModelsClientVersion,
      codexClientVersion,
    );
  });
}
