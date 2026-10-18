import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/models/model_spec.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/native_input_attachments.dart';
import 'package:Kelivo/core/services/api/providers/openai/chat_completions_api.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';

import 'support/claude_test_api.dart' show FakePathProviderPlatform;

/// 工具返回图片后，历史回放要能在**后续请求**里继续把那张图发给模型。
/// 图片本身在工具消息的 `metadata` 里，所以续跑复制消息时必须保住它；
/// 但它只是本地存档信息，最终发给供应商的请求体里不能出现。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late String imagePath;
  late String expectedBase64;
  late Map<String, dynamic> metadata;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('openai_tool_images_');
    await Directory('${directory.path}/images').create();
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(directory.path);
    SandboxPathResolver.debugSetDirs(docsDir: directory.path);
    final file = File('${directory.path}/images/mcp_img_plot.png');
    final bytes = img.encodePng(img.Image(width: 2, height: 3));
    await file.writeAsBytes(bytes);
    imagePath = file.path;
    expectedBase64 = base64Encode(bytes);
    metadata = {
      kMcpResultMetadataKey: mcpResultMetadata([file.path]),
    };
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPaths;
    SandboxPathResolver.debugSetDirs();
    await directory.delete(recursive: true);
  });

  List<String> imageUrls(List<Map<String, dynamic>> built) {
    final urls = <String>[];
    void walk(Object? node) {
      if (node is Map) {
        for (final entry in node.entries) {
          if (entry.key == 'image_url' && entry.value is Map) {
            urls.add((entry.value as Map)['url'].toString());
          } else {
            walk(entry.value);
          }
        }
      } else if (node is List) {
        for (final item in node) {
          walk(item);
        }
      }
    }

    walk(built);
    return urls;
  }

  Future<List<Map<String, dynamic>>> build(List<Map<String, dynamic>> copied) {
    return buildOpenAIChatCompletionMessages(
      copied,
      nativeInputs: NativeInputAttachments(
        config: ProviderConfig(
          id: 'test',
          enabled: true,
          name: 'test',
          apiKey: '',
          baseUrl: 'https://api.example.com/v1',
        ),
        spec: ModelSpec(id: 'test', displayName: 'test'),
        protocol: NativeInputProtocol.chatCompletions,
      ),
      canImageInput: true,
      allowRemoteImages: false,
      reasoningReplay: ReasoningReplayPolicy.all,
    );
  }

  List<Map<String, dynamic>> history() => [
    {'role': 'user', 'content': '画个图'},
    {
      'role': 'assistant',
      'content': '',
      'tool_calls': [
        {
          'id': 'call_image',
          'type': 'function',
          'function': {'name': 'view_drawing', 'arguments': '{}'},
        },
      ],
    },
    {
      'role': 'tool',
      'name': 'view_drawing',
      'tool_call_id': 'call_image',
      'content': 'drawing\n![](${encodeMarkdownImageDestination(imagePath)})',
      'metadata': metadata,
    },
    {'role': 'user', 'content': '再画一次'},
  ];

  test('续跑复制后历史图片仍会随请求发出', () async {
    final copied = history().map(copyChatCompletionMessage).toList();
    expect(
      copied.singleWhere((m) => m['role'] == 'tool')['metadata'],
      isNotNull,
      reason: '丢掉元数据就等于丢掉这张历史图片',
    );

    final built = await build(copied);
    expect(imageUrls(built), [
      'data:image/png;base64,$expectedBase64',
    ], reason: '回放历史时那张图要照旧发给模型');
  });

  test('图片存档信息不会出现在请求体里，本机路径也不外发', () async {
    final built = await build(
      history().map(copyChatCompletionMessage).toList(),
    );
    final wire = jsonEncode(built);
    expect(
      wire,
      isNot(contains(kMcpResultMetadataKey)),
      reason: '本地存档信息不该发给供应商',
    );
    expect(wire, isNot(contains(imagePath)), reason: '发给模型的应当是图片本体，不是本机路径');
  });

  test('只有工具消息会带上元数据，其它角色不受影响', () async {
    final copied = copyChatCompletionMessage({
      'role': 'user',
      'content': '画个图',
      'metadata': metadata,
    });
    expect(copied.containsKey('metadata'), isFalse);
  });
}
