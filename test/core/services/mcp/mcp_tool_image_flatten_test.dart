import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/services/api/tool_result_content.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';

import '../../../support/business_test_harness.dart';
import '../../../support/claude_test_api.dart' show FakePathProviderPlatform;

/// MCP 服务端返回图片有两种形态：带内容的（`data`）和只给网址的（`url`）。
/// 前者直接落成本机快照；后者在工具执行时下载一次再落盘，于是历史回放
/// 不必每次都联网，也不会把服务端那边的本机路径当成客户端文件。
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jTioAAAAASUVORK5CYII=';

Future<Directory> _prepareImageDirectory() async {
  final directory = await Directory.systemTemp.createTemp('mcp_pixels_');
  final originalPaths = PathProviderPlatform.instance;
  PathProviderPlatform.instance = FakePathProviderPlatform(directory.path);
  SandboxPathResolver.debugSetDirs(docsDir: directory.path);
  addTearDown(() async {
    PathProviderPlatform.instance = originalPaths;
    SandboxPathResolver.debugSetDirs();
    await directory.delete(recursive: true);
  });
  return directory;
}

Future<McpToolResult> _flatten(
  List<mcp.Content> content, {
  String name = 'shot',
}) async {
  final provider = _ContentMcpProvider(content);
  final assistants = AssistantProvider(
    preferences: createBusinessTestPreferences(),
  );
  final service = McpToolService();
  addTearDown(provider.dispose);
  addTearDown(assistants.dispose);
  addTearDown(service.dispose);
  await assistants.loaded;
  final assistantId = await assistants.addAssistant(name: 'Test');
  await assistants.updateAssistant(
    assistants.getById(assistantId)!.copyWith(mcpServerIds: const ['srv-id']),
  );
  return service.callToolForAssistant(
    provider,
    assistants,
    assistantId: assistantId,
    toolName: name,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('图片内容落成快照，服务端的本机路径不会被当成客户端文件', () async {
    final directory = await _prepareImageDirectory();
    final private = File('${directory.path}/images/private.png');
    await private.create(recursive: true);
    await private.writeAsBytes(base64Decode(_png));

    final raw = await _flatten([
      const mcp.TextContent(text: 'drawing'),
      const mcp.ImageContent(data: _png, mimeType: 'image/png'),
      // 这三种写法都指向服务端那边的一个文件，客户端一律不认。
      mcp.ImageContent(url: private.path, mimeType: 'image/png'),
      mcp.ImageContent(url: private.uri.toString(), mimeType: 'image/png'),
      mcp.ImageContent(
        url: SandboxPathResolver.canonicalize(private.path),
        mimeType: 'image/png',
      ),
    ]);

    expect(raw.imageUris, hasLength(1));
    expect(
      raw.imageUris.single,
      startsWith('kelivo-file:///images/mcp_img_'),
      reason: '只有带内容的图片才会落成快照',
    );
    expect(raw.markdown, isNot(contains('private.png')));

    final media = await ToolResultContent.read(
      'shot',
      raw.markdown,
      metadata: {kMcpResultMetadataKey: mcpResultMetadata(raw.imageUris)},
    );
    expect(media.text, 'drawing');
    expect(media.imageUrls, ['data:image/png;base64,$_png']);
  });

  test('只给网址的图片在工具执行时下载一次并落盘，重复网址不重复下载', () async {
    await _prepareImageDirectory();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <String>[];
    server.listen((request) async {
      requests.add(request.uri.path);
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(base64Decode(_png));
      await request.response.close();
    });
    final baseUrl = 'http://127.0.0.1:${server.port}';

    final raw = await _flatten([
      mcp.TextContent(text: 'caption A'),
      mcp.ImageContent(url: '$baseUrl/a.png', mimeType: 'image/png'),
      mcp.TextContent(text: 'caption B'),
      mcp.ImageContent(url: '$baseUrl/b.png', mimeType: 'image/png'),
      mcp.ImageContent(url: '$baseUrl/a.png', mimeType: 'image/png'),
    ]);

    expect(requests, ['/a.png', '/b.png'], reason: '同一个网址只下一次');
    expect(raw.imageUris, hasLength(2));
    for (final uri in raw.imageUris) {
      expect(uri, startsWith('kelivo-file:///images/mcp_img_'));
    }
    // 文字与图片的先后顺序原样保留，重复的图片在正文里也按原序出现。
    expect(
      RegExp(r'caption A').firstMatch(raw.markdown)!.start,
      lessThan(RegExp(r'caption B').firstMatch(raw.markdown)!.start),
    );
    expect('![]('.allMatches(raw.markdown).length, 3, reason: '三张图片位置一个不少');
    final media = await ToolResultContent.read(
      'shot',
      raw.markdown,
      metadata: {kMcpResultMetadataKey: mcpResultMetadata(raw.imageUris)},
    );
    expect(
      media.imageUrls,
      List.filled(2, 'data:image/png;base64,$_png'),
      reason: '重复的图片在送给模型时只算一次',
    );
  });

  test('下载失败时只丢这一张图，其余内容照常返回', () async {
    await _prepareImageDirectory();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final raw = await _flatten([
      const mcp.TextContent(text: '画不出'),
      mcp.ImageContent(
        url: 'http://127.0.0.1:${server.port}/missing.png',
        mimeType: 'image/png',
      ),
    ]);

    expect(raw.imageUris, isEmpty);
    expect(raw.markdown, '画不出');
  });
}

class _ContentMcpProvider extends McpProvider {
  _ContentMcpProvider(this._content)
    : super(preferences: createBusinessTestPreferences());

  final List<mcp.Content> _content;

  @override
  List<McpServerConfig> get servers => [
    McpServerConfig(
      id: 'srv-id',
      enabled: true,
      name: 'srv',
      transport: McpTransportType.http,
      tools: [McpToolConfig(enabled: true, name: 'shot')],
    ),
  ];

  @override
  Future<void> connect(String id) async {}

  @override
  Future<mcp.CallToolResult?> callTool(
    String serverId,
    String toolName,
    Map<String, dynamic> args,
  ) async {
    return mcp.CallToolResult(_content);
  }
}
