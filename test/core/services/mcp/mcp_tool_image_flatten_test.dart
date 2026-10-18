import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mcp_client/mcp_client.dart' as mcp;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/services/api/tool_result_content.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';
import 'package:Kelivo/core/services/tool_image.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';

import '../../../support/business_test_harness.dart';
import '../../../support/claude_test_api.dart' show FakePathProviderPlatform;

/// MCP 服务端返回图片有两种形态：带内容的（`data`）和只给网址的（`url`）。
/// 前者直接落成本机快照；后者在工具执行时下载一次再落盘，于是历史回放
/// 不必每次都联网，也不会把服务端那边的本机路径当成客户端文件。
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=';

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
    // 服务端本地路径的图片会被丢掉，但会留一行提醒；文字仍原样保留。
    expect(media.text, startsWith('drawing'));
    expect(
      '(Image omitted'.allMatches(media.text).length,
      3,
      reason: '三张服务端本地路径的图各留一行提醒',
    );
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
    // 下载失败时保留文字，并附一行提醒而不是静默丢掉。
    expect(raw.markdown, startsWith('画不出'));
    expect(raw.markdown, contains('(Image omitted'));
  });

  // 工具图片在继续对话和历史回放里必须是一份“能直接用”的快照：
  // 只在第一个回合碰巧能显示不算数。
  for (final format in [
    'jpeg_parameters',
    'bmp',
    'long_png',
    'invalid',
    'corrupt_png',
  ]) {
    test('MCP $format 在继续对话和历史回放里都能安全使用', () async {
      await _prepareImageDirectory();
      final pixels = img.Image(
        width: format == 'long_png' ? 16 : 3,
        height: format == 'long_png' ? 9000 : 2,
      );
      img.fill(pixels, color: img.ColorRgb8(240, 10, 40));
      final bytes = switch (format) {
        'jpeg_parameters' => img.encodeJpg(pixels),
        'bmp' => img.encodeBmp(pixels),
        'invalid' => utf8.encode('<svg>unsupported</svg>'),
        'corrupt_png' => base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jTioAAAAASUVORK5CYII=',
        ),
        _ => img.encodePng(pixels),
      };
      final mime = switch (format) {
        'jpeg_parameters' => 'image/jpeg; charset=binary',
        'bmp' => 'image/bmp',
        'invalid' => 'image/svg+xml',
        _ => 'image/png',
      };
      final raw = await _flatten([
        mcp.ImageContent.fromJson({
          'type': 'image',
          'mimeType': mime,
          'data': base64Encode(bytes),
        }),
      ]);
      final metadata = {
        kMcpResultMetadataKey: mcpResultMetadata(raw.imageUris),
      };
      for (final current in [
        metadata,
        (jsonDecode(jsonEncode(metadata)) as Map).cast<String, dynamic>(),
      ]) {
        final media = await ToolResultContent.read(
          'shot',
          raw.markdown,
          metadata: current,
        );
        if (format == 'invalid' || format == 'corrupt_png') {
          expect(raw.imageUris, isEmpty);
          expect(media.imageUrls, isEmpty);
          expect(media.text, contains('Image omitted'));
          continue;
        }
        expect(raw.imageUris, hasLength(1), reason: '$format stored');
        expect(media.imageUrls, hasLength(1), reason: '$format read');
        final data = Uri.parse(media.imageUrls.single).data!;
        final encoded = data.contentAsBytes();
        final decoder = img.findDecoderForData(encoded)!;
        expect(
          data.mimeType,
          decoder.format == img.ImageFormat.jpg ? 'image/jpeg' : 'image/png',
        );
        expect(
          decoder.format,
          isIn([img.ImageFormat.png, img.ImageFormat.jpg]),
        );
        final decoded = img.decodeImage(encoded)!;
        expect(decoded.width, lessThanOrEqualTo(ToolImage.maxLongEdge));
        expect(decoded.height, lessThanOrEqualTo(ToolImage.maxLongEdge));
        expect(decoded.getPixel(0, 0).r, greaterThan(220));
        final stored = File(
          SandboxPathResolver.resolveForIo(raw.imageUris.single)!,
        );
        expect(await stored.readAsBytes(), encoded);
        expect(
          raw.imageUris.single,
          endsWith(data.mimeType == 'image/jpeg' ? '.jpg' : '.png'),
        );
      }
    });
  }
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
