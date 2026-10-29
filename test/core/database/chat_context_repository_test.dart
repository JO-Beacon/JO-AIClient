import 'dart:io';

import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/context_operation.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatContextRepository', () {
    late Directory directory;
    late ChatDatabaseRepository repository;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'kelivo_context_repository_test_',
      );
      repository = ChatDatabaseRepository.open(
        file: File('${directory.path}/chat.sqlite'),
      );
      await repository.ensureReady();
    });

    tearDown(() async {
      await repository.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    Future<void> seed({
      String id = 'conversation',
      int truncateIndex = -1,
      int messageCount = 4,
    }) async {
      final now = DateTime.utc(2026, 10, 1);
      final messages = [
        for (var i = 0; i < messageCount; i++)
          ChatMessage(
            id: 'g$i',
            role: i.isEven ? 'user' : 'assistant',
            content: 'message $i',
            conversationId: id,
            groupId: 'g$i',
            timestamp: now.add(Duration(minutes: i)),
          ),
      ];
      await repository.putMigrationBatch(
        conversations: [
          Conversation(
            id: id,
            title: 'Context test',
            createdAt: now,
            updatedAt: now,
            messageIds: messages.map((message) => message.id).toList(),
            truncateIndex: truncateIndex,
          ),
        ],
        messages: [
          for (var i = 0; i < messages.length; i++)
            (message: messages[i], messageOrder: i),
        ],
        toolEventsByMessageId: const {},
        geminiSignaturesByMessageId: const {},
      );
    }

    Future<ContextOperation> appendClear() async {
      final snapshot = await repository.readContextSnapshot('conversation');
      final clear = ContextOperation(
        id: 'clear-1',
        kind: ContextOperationKind.clear,
        anchorGroupId: 'g1',
        appliedAfterGroupId: 'g1',
        sourceGroups: const ['g0', 'g1'],
        dependencies: const [],
        createdAt: DateTime.utc(2026, 10, 2),
      );
      await repository.appendContextOperation(
        'conversation',
        clear,
        expectedFingerprint: snapshot.fingerprint,
      );
      return clear;
    }

    test('converts legacy truncateIndex into a clear operation', () async {
      await seed(truncateIndex: 2);

      final operations = await repository.readContextOperations('conversation');
      final conversation = await repository.getConversation('conversation');

      expect(conversation!.truncateIndex, -1);
      expect(operations, hasLength(1));
      expect(operations.single.kind, ContextOperationKind.clear);
      expect(operations.single.anchorGroupId, 'g1');
      expect(operations.single.sourceGroups, ['g0', 'g1']);
      expect(operations.single.convertedFromLegacyClear, isTrue);

      final effective = await repository.getEffectiveContextMessages(
        'conversation',
        limit: 100,
      );
      expect(effective.map((message) => message.content), [
        'message 2',
        'message 3',
      ]);
    });

    test('clear and undo survive a repository round trip', () async {
      await seed();
      final clear = await appendClear();

      expect(
        (await repository.getEffectiveContextMessages(
          'conversation',
          limit: 100,
        )).map((message) => message.content),
        ['message 2', 'message 3'],
      );

      final operations = await repository.readContextOperations('conversation');
      await repository.changeContextOperation(
        'conversation',
        clear.id,
        includeDependents: true,
        expectedState: ContextHistory.operationsFingerprint(operations),
      );

      expect(
        (await repository.getEffectiveContextMessages(
          'conversation',
          limit: 100,
        )).map((message) => message.content),
        ['message 0', 'message 1', 'message 2', 'message 3'],
      );
    });

    test('compression task records persist per conversation', () async {
      await seed();

      await repository.saveCompressionTask('conversation', {
        'id': 'task-1',
        'phase': 'waiting',
        'summary': '',
      });

      final tasks = await repository.readCompressionTasks();
      expect(tasks['conversation'], {
        'id': 'task-1',
        'phase': 'waiting',
        'summary': '',
      });
    });

    test('duplicate conversation remaps context operations', () async {
      await seed();
      await appendClear();

      final duplicate = await repository.duplicateConversation('conversation');
      expect(duplicate, isNotNull);

      final operations = await repository.readContextOperations(duplicate!.id);
      expect(operations, hasLength(1));
      expect(operations.single.convertedFromLegacyClear, isFalse);
      expect(operations.single.anchorGroupId, isNot('g1'));
      expect(
        await repository.getEffectiveContextMessages(duplicate.id, limit: 100),
        hasLength(2),
      );
    });

    test('deleting a conversation removes context records', () async {
      await seed();
      await appendClear();
      await repository.saveCompressionTask('conversation', {'id': 'task-1'});

      await repository.deleteConversation('conversation');

      expect(await repository.getConversation('conversation'), isNull);
      expect(await repository.readCompressionTasks(), isEmpty);
    });
  });
}
