import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/models/context_operation.dart';
import 'package:Kelivo/core/models/conversation.dart';
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
    tempDir = await Directory.systemTemp.createTemp('kelivo_context_merge_');
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

  test('merged backup keeps clear operations and effective context', () async {
    final conversation = await chat.createConversation(title: 'Merge');
    final id = conversation.id;
    await chat.addMessage(
      conversationId: id,
      role: 'user',
      content: 'first question',
    );
    await chat.addMessage(
      conversationId: id,
      role: 'assistant',
      content: 'first answer',
    );
    await chat.addMessage(
      conversationId: id,
      role: 'user',
      content: 'second question',
    );
    await chat.clearConversationContext(id);

    final before = await chat.loadContextOperations(id, refresh: true);
    expect(before, hasLength(1));
    expect(before.single.kind, ContextOperationKind.clear);

    final snapshot = File('${tempDir.path}/context-merge.sqlite');
    await chat.createBackupDatabaseSnapshot(snapshot);
    await chat.deleteConversation(id);
    expect(chat.getConversation(id), isNull);

    final report = await chat.mergeDatabaseSnapshot(snapshot);
    expect(report.importedConversationIds, contains(id));

    final after = await chat.loadContextOperations(id, refresh: true);
    expect(after, hasLength(1));
    expect(after.single.kind, ContextOperationKind.clear);
    expect(after.single.revoked, isFalse);

    final effective = await chat.loadEffectiveContextMessages(id, limit: 100);
    expect(effective, isEmpty);
  });
  test('merged backup remaps clear operations with the conversation', () async {
    final conversation = await chat.createConversation(title: 'Remap');
    final id = conversation.id;
    await chat.addMessage(
      conversationId: id,
      role: 'user',
      content: 'remap question',
    );
    await chat.addMessage(
      conversationId: id,
      role: 'assistant',
      content: 'remap answer',
    );
    await chat.clearConversationContext(id);

    final snapshot = File('${tempDir.path}/context-remap.sqlite');
    await chat.createBackupDatabaseSnapshot(snapshot);
    await chat.deleteConversation(id);

    // Reuse the source id with different content so the merge has to remap
    // both the conversation and every message the operation references.
    await chat.chatRepositoryOrNull!.putConversation(
      Conversation(id: id, title: 'Conflicting local conversation'),
    );
    final report = await chat.mergeDatabaseSnapshot(snapshot);
    final targetId = report.remappedConversationIds[id];
    expect(targetId, isNotNull);
    expect(targetId, isNot(id));

    final operations = await chat.loadContextOperations(
      targetId!,
      refresh: true,
    );
    expect(operations, hasLength(1));
    expect(operations.single.kind, ContextOperationKind.clear);
    expect(operations.single.anchorGroupId, isNot(anyOf(isEmpty)));

    final effective = await chat.loadEffectiveContextMessages(
      targetId,
      limit: 100,
    );
    expect(effective, isEmpty);
  });

}
