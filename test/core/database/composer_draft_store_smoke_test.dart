import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/composer_draft_store.dart';
import 'package:Kelivo/core/models/composer_draft.dart';
import 'package:Kelivo/core/models/conversation.dart';

/// 数据层冒烟：草稿按会话独立保存、清空即删、新会话草稿按助手复用。
void main() {
  late Directory root;
  late AppDatabase db;
  late ComposerDraftStore store;

  Future<void> open() async {
    db = AppDatabase(NativeDatabase(File('${root.path}/drafts.db')));
    store = ComposerDraftStore(
      db,
      directory: () async => Directory('${root.path}/files'),
    );
    await store.initialize();
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('composer-draft-smoke-');
    await open();
  });

  tearDown(() async {
    store.dispose();
    await db.close();
    await root.delete(recursive: true);
  });

  Conversation conversation(String id, {String? assistantId}) =>
      Conversation(id: id, title: 't', assistantId: assistantId);

  test('写入后 flush，重开数据库仍能读回', () async {
    await store.load('c1');
    store.setInput(
      'c1',
      const ComposerDraftInput(
        text: '未发送的草稿',
        selectionBase: 2,
        selectionExtent: 5,
      ),
    );
    expect(store.hasDraft('c1'), isTrue);
    await store.flush();

    store.dispose();
    await db.close();
    await open();

    final draft = await store.load('c1');
    expect(draft.compose.text, '未发送的草稿');
    expect(draft.compose.selectionBase, 2);
    expect(draft.compose.selectionExtent, 5);
  });

  test('不同会话的草稿互不影响', () async {
    await store.load('a');
    await store.load('b');
    store.setInput('a', const ComposerDraftInput(text: 'A 的内容'));
    store.setInput('b', const ComposerDraftInput(text: 'B 的内容'));
    await store.flush();

    expect((await store.load('a')).compose.text, 'A 的内容');
    expect((await store.load('b')).compose.text, 'B 的内容');
  });

  test('清空内容后草稿从记录中消失', () async {
    await store.load('c1');
    store.setInput('c1', const ComposerDraftInput(text: '有内容'));
    await store.flush();
    expect(store.hasDraft('c1'), isTrue);

    store.setInput('c1', const ComposerDraftInput());
    await store.flush();
    expect(store.hasDraft('c1'), isFalse);

    final rows = await db
        .customSelect(
          "SELECT COUNT(*) AS n FROM extension_entity_rows WHERE kind = 'composerDraft'",
        )
        .getSingle();
    expect(rows.read<int>('n'), 0);
  });

  test('删除会话时草稿一并删除', () async {
    await store.load('c1');
    store.setInput('c1', const ComposerDraftInput(text: '要删掉'));
    await store.flush();

    await store.delete('c1');
    expect(store.hasDraft('c1'), isFalse);
    expect(() => store.load('c1'), throwsStateError);
  });

  test('新会话草稿按助手复用', () async {
    final first = conversation('new-1', assistantId: 'as-1');
    store.registerNewEntry(first);
    expect(store.newEntry('as-1')?.id, 'new-1');

    store.registerNewEntry(conversation('new-2', assistantId: 'as-1'));
    expect(store.newEntry('as-1')?.id, 'new-2');
    expect(store.newEntry('as-2'), isNull);
  });
}
