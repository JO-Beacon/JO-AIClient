import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/models/compress_context_options.dart';
import 'package:Kelivo/core/models/context_compression_task.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationCachePath() async => '$path/cache';

  @override
  Future<String?> getTemporaryPath() async => '$path/tmp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ChatService chat;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kelivo_compression_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    SandboxPathResolver.debugSetDirs(
      docsDir: tempDir.path,
      supportDir: tempDir.path,
    );
    chat = ChatService();
    await chat.init();
  });

  tearDown(() async {
    await chat.close();
    await Hive.close();
    SandboxPathResolver.debugSetDirs(docsDir: null, supportDir: null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('new-conversation compression seeds a copy and keeps the source', () async {
    final conversation = await chat.createConversation(title: 'Source');
    final id = conversation.id;
    await chat.setConversationModel(id, providerKey: 'p', modelId: 'm');
    await chat.setConversationMcpServers(id, const ['server-1']);
    await chat.addMessage(
      conversationId: id,
      role: 'user',
      content: 'first question with enough words for a summary',
    );
    await chat.addMessage(
      conversationId: id,
      role: 'assistant',
      content: 'first answer',
    );
    await chat.addMessage(
      conversationId: id,
      role: 'user',
      content: 'second question to retain',
    );

    await chat.contextCompression.start(
      id,
      CompressionRequest(
        options: const CompressContextOptions(
          mode: CompressContextLimitMode.keepRecent,
          keepUserMessages: 1,
          newConversation: true,
        ),
        model: 'test-model',
        generate: (content, requestId) async => 'short summary',
      ),
    );
    await chat.contextCompression.waitForTask(id);

    final task = chat.contextCompression.taskFor(id);
    expect(task, isNotNull);
    expect(task!.phase, CompressionPhase.completed);
    expect(task.resultConversationId, isNotNull);

    final created = chat.getConversation(task.resultConversationId!);
    expect(created, isNotNull);
    expect(created!.id, isNot(id));
    expect(created.chatModelProvider, 'p');
    expect(created.chatModelId, 'm');
    expect(created.mcpServerIds, ['server-1']);

    final sourceMessages = await chat.loadMessages(id);
    final copiedMessages = await chat.loadMessages(created.id);
    expect(sourceMessages, hasLength(3));
    expect(copiedMessages.first.content, 'short summary');
    expect(copiedMessages.last.content, 'second question to retain');
    expect(copiedMessages.length, lessThan(sourceMessages.length + 1));
  });

  test('waitForTask stops at review instead of throwing', () async {
    final conversation = await chat.createConversation(title: 'Review');
    final id = conversation.id;
    await chat.addMessage(
      conversationId: id,
      role: 'user',
      content: 'short history',
    );

    await chat.contextCompression.start(
      id,
      CompressionRequest(
        options: const CompressContextOptions(
          mode: CompressContextLimitMode.unlimited,
        ),
        model: 'test-model',
        generate: (content, requestId) async => 'summary ' * 4000,
      ),
    );

    await chat.contextCompression.waitForTask(id);

    final task = chat.contextCompression.taskFor(id);
    expect(task, isNotNull);
    expect(task!.phase, CompressionPhase.review);
    expect(task.error, 'summary_not_smaller');
  });
}
