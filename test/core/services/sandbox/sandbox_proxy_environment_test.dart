import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/sandbox/sandbox_proxy_environment.dart';

import '../../../support/business_test_harness.dart';

/// 沙箱里的 curl／git 这类程序靠标准代理环境变量走代理。
/// 这里守的是：代理只在用户真配好时才注入、注入的是**进程级默认值**（不写进
/// 用户的环境变量列表）、客户机自己设过的值优先、以及 no_proxy 的规则不能被
/// 悄悄放宽或收紧。
Future<SettingsProvider> _settings({
  Map<String, Object?> overrides = const {},
}) async {
  final harness = await createBusinessTestHarness(
    initial: {
      'global_proxy_enabled_v1': true,
      'global_proxy_type_v1': 'http',
      'global_proxy_host_v1': '127.0.0.1',
      'global_proxy_port_v1': '7890',
      ...overrides,
    },
  );
  final settings = SettingsProvider(harness.preferences);
  addTearDown(settings.dispose);
  await settings.loaded;
  return settings;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('已配置代理时注入标准代理变量，且不产生 HTTP_PROXY 这个拼写', () async {
    final settings = await _settings(
      overrides: {
        'global_proxy_bypass_v1': 'localhost; 127.0.0.1,*.example.test',
      },
    );

    final variables = sandboxProxyEnvironment(settings, const {});

    expect(variables, {
      'http_proxy': 'http://127.0.0.1:7890',
      'https_proxy': 'http://127.0.0.1:7890',
      'HTTPS_PROXY': 'http://127.0.0.1:7890',
      'all_proxy': 'http://127.0.0.1:7890',
      'ALL_PROXY': 'http://127.0.0.1:7890',
      'no_proxy': 'localhost,127.0.0.1,.example.test',
      'NO_PROXY': 'localhost,127.0.0.1,.example.test',
    });
    expect(
      variables.containsKey('HTTP_PROXY'),
      isFalse,
      reason: 'curl 会忽略它，没必要自己引入这个拼写',
    );
  });

  test('代理默认值只是快照，不会写进用户的环境变量列表', () async {
    final settings = await _settings();
    final harness = await createBusinessTestHarness();
    final env = EnvironmentProvider(
      preferences: harness.preferences,
      proxySettings: settings,
    );
    addTearDown(env.dispose);

    final config = await env.loadExecutionConfig();

    expect(config.variables['http_proxy'], 'http://127.0.0.1:7890');
    expect(env.variables, isEmpty, reason: '不能把默认值写进用户列表');

    final withoutProxy = EnvironmentProvider(preferences: harness.preferences);
    addTearDown(withoutProxy.dispose);
    expect((await withoutProxy.loadExecutionConfig()).variables, isEmpty);
  });

  for (final (label, key, value) in <(String, String, Object?)>[
    ('代理开关关闭', 'global_proxy_enabled_v1', false),
    ('主机为空', 'global_proxy_host_v1', '   '),
    ('端口为 0', 'global_proxy_port_v1', '0'),
    ('端口超出范围', 'global_proxy_port_v1', '70000'),
    ('端口不是数字', 'global_proxy_port_v1', 'abc'),
  ]) {
    test('配置不完整时不注入任何代理（$label）', () async {
      final settings = await _settings(overrides: {key: value});
      expect(sandboxProxyEnvironment(settings, const {}), isEmpty);
    });
  }

  test('socks5 用 socks5h，其它类型都用 http', () async {
    final socks = await _settings(
      overrides: {'global_proxy_type_v1': 'socks5'},
    );
    expect(
      sandboxProxyEnvironment(socks, const {})['http_proxy'],
      'socks5h://127.0.0.1:7890',
      reason: '让代理侧解析域名',
    );
    final https = await _settings(overrides: {'global_proxy_type_v1': 'https'});
    expect(
      sandboxProxyEnvironment(https, const {})['http_proxy'],
      'http://127.0.0.1:7890',
    );
  });

  test('带用户名密码时按 URI 编码写入 userInfo', () async {
    final settings = await _settings(
      overrides: {
        'global_proxy_username_v1': 'user@name',
        'global_proxy_password_v1': 'p@ss:word/中文',
      },
    );

    final proxy = sandboxProxyEnvironment(settings, const {})['http_proxy']!;
    final uri = Uri.parse(proxy);
    expect(uri.userInfo, isNotEmpty);
    expect(Uri.decodeComponent(uri.userInfo.split(':').first), 'user@name');
    expect(Uri.decodeComponent(uri.userInfo.split(':').last), 'p@ss:word/中文');
    expect(uri.host, '127.0.0.1');
    expect(uri.port, 7890);
  });

  test('只填了密码、没填用户名时不生成认证段', () async {
    final settings = await _settings(
      overrides: {'global_proxy_password_v1': 'secret'},
    );
    expect(
      sandboxProxyEnvironment(settings, const {})['http_proxy'],
      'http://127.0.0.1:7890',
    );
  });

  test('客户机自己设过的值优先，小写与大写都算', () async {
    final settings = await _settings();

    expect(
      sandboxProxyEnvironment(settings, const {
        'http_proxy': 'http://guest.test:8081',
      })['http_proxy'],
      'http://guest.test:8081',
    );
    expect(
      sandboxProxyEnvironment(settings, const {
        'HTTPS_PROXY': 'http://guest.test:8081',
      })['https_proxy'],
      'http://guest.test:8081',
      reason: '大写拼写同样要被尊重',
    );
    // 客户机只设了 all_proxy 时，http/https 也应当沿用它。
    final withAll = sandboxProxyEnvironment(settings, const {
      'all_proxy': 'socks5h://guest.test:1080',
    });
    expect(withAll['http_proxy'], 'socks5h://guest.test:1080');
    expect(withAll['https_proxy'], 'socks5h://guest.test:1080');
  });

  test('no_proxy 规则：去掉星号前缀，丢掉无法通用表达的模式，保留全放行', () async {
    final settings = await _settings(
      overrides: {'global_proxy_bypass_v1': '*.example.com,foo*bar,*'},
    );
    expect(
      sandboxProxyEnvironment(settings, const {})['no_proxy'],
      '.example.com,*',
    );
  });

  test('会话级 overrides 与代理默认值共存，且 overrides 优先', () async {
    final settings = await _settings();
    final variables = sandboxProxyEnvironment(settings, const {
      'MY_TOKEN': 'abc',
      'http_proxy': 'http://session.test:1',
    });

    expect(variables['MY_TOKEN'], 'abc');
    expect(variables['http_proxy'], 'http://session.test:1');
    expect(variables['https_proxy'], 'http://127.0.0.1:7890');
  });

  test('主机字段填了 Uri 不接受的内容时不抛异常，也不注入代理', () async {
    // 常见情形：把一段网址粘进了主机框。Uri 会直接报错，此时不能因此让
    // 本地的 shell／文件工具都跑不了，所以按“未配置代理”处理。
    final settings = await _settings(
      overrides: {'global_proxy_host_v1': 'example.test/path'},
    );
    expect(sandboxProxyEnvironment(settings, const {}), isEmpty);
  });

  test('主机框里带空格时会被百分号编码后注入（记录当前行为）', () async {
    final settings = await _settings(
      overrides: {'global_proxy_host_v1': 'bad host name'},
    );
    // 这里记录当前行为：空格会被百分号编码成一个能解析但不指向任何主机的地址。
    final variables = sandboxProxyEnvironment(settings, const {});
    expect(variables['http_proxy'], 'http://bad%20host%20name:7890');
  });
}
