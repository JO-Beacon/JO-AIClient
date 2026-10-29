part of 'chat_service.dart';

typedef ConversationContextSnapshot = ({
  List<ChatMessage> messages,
  List<ContextOperation> operations,
  String fingerprint,
});

extension ChatContextOperations on ChatService {
  Future<Map<String, Map<String, dynamic>>> readCompressionTaskRecords() =>
      _repo.readCompressionTasks();

  Future<void> saveCompressionTaskRecord(
    String id,
    Map<String, dynamic> record,
  ) async {
    if (!_initialized ||
        _temporaryConversationIds.contains(id) ||
        _draftConversations.containsKey(id)) {
      return;
    }
    await _repo.saveCompressionTask(id, record);
  }

  Future<List<ContextOperation>> loadContextOperations(
    String id, {
    bool refresh = false,
  }) async {
    if (!_initialized) return [];
    if (!refresh &&
        _contextOperations.containsKey(id) &&
        _contextStateVersions[id] == contextRevision(id)) {
      return contextOperationsFor(id);
    }
    if (_temporaryConversationIds.contains(id) ||
        _draftConversations.containsKey(id)) {
      final operations = _contextOperations[id] ?? const <ContextOperation>[];
      _contextStateVersions[id] = contextRevision(id);
      return List<ContextOperation>.of(operations);
    }
    final revision = contextRevision(id);
    final operations = await _repo.readContextOperations(id);
    if (revision != contextRevision(id)) {
      return loadContextOperations(id, refresh: true);
    }
    _contextOperations[id] = List<ContextOperation>.of(operations);
    _contextStartIndices[id] = await _repo.contextBoundaryIndex(id, operations);
    _contextStateVersions[id] = contextRevision(id);
    final conversation = _conversationsCache[id];
    if (conversation != null) conversation.truncateIndex = -1;
    return contextOperationsFor(id);
  }

  Future<ConversationContextSnapshot> loadContextSnapshot(String id) async {
    if (!_temporaryConversationIds.contains(id) &&
        !_draftConversations.containsKey(id)) {
      final snapshot = await _repo.readContextSnapshot(id);
      _conversationsCache[id]?.truncateIndex = -1;
      await _cacheMessageArtifacts(snapshot.messages);
      return snapshot;
    }
    final operations = await loadContextOperations(id);
    final raw = await loadRawSelectedContextMessages(id, limit: 0x7fffffff);
    return (
      messages: raw,
      operations: operations,
      fingerprint: ContextHistory.fingerprint(raw, operations),
    );
  }

  Future<List<ChatMessage>> _loadEffectiveContextMessages(
    String conversationId, {
    required int limit,
    String? throughRevisionId,
    bool includeFollowingAssistant = false,
  }) async {
    if (!_initialized || limit <= 0) return const <ChatMessage>[];
    if (!_temporaryConversationIds.contains(conversationId) &&
        !_draftConversations.containsKey(conversationId)) {
      await loadContextOperations(conversationId);
      final messages = await _repo.getEffectiveContextMessages(
        conversationId,
        limit: limit,
        throughRevisionId: throughRevisionId,
        includeFollowingAssistant: includeFollowingAssistant,
      );
      await _cacheMessageArtifacts(
        messages.where((m) => !ContextOperation.isSummary(m)).toList(),
      );
      return messages;
    }
    final operations = await loadContextOperations(conversationId);
    final raw = await loadRawSelectedContextMessages(
      conversationId,
      limit: 0x7fffffff,
    );
    String? throughGroup;
    String? endGroup;
    if (throughRevisionId != null) {
      final target = (_messagesCache[conversationId] ?? const [])
          .where((m) => m.id == throughRevisionId)
          .firstOrNull;
      if (target == null) return [];
      throughGroup = ContextHistory.group(target);
      endGroup = throughGroup;
      final index = raw.indexWhere(
        (m) => ContextHistory.group(m) == throughGroup,
      );
      if (includeFollowingAssistant &&
          target.role == 'user' &&
          index >= 0 &&
          index + 1 < raw.length &&
          raw[index + 1].role == 'assistant') {
        endGroup = ContextHistory.group(raw[index + 1]);
      }
    }
    return ContextHistory.resolve(
      raw,
      ContextHistory.applicable(operations, raw),
      limit: limit,
      throughGroupId: throughGroup,
      endGroupId: endGroup,
    );
  }

  /// Raw selected path reader used by snapshots and original-history views.
  /// Model requests must use [loadEffectiveContextMessages].
  Future<List<ChatMessage>> loadRawSelectedContextMessages(
    String conversationId, {
    required int limit,
  }) {
    return loadSelectedContextMessages(
      conversationId,
      truncateIndex: -1,
      limit: limit,
    );
  }

  Future<List<ChatMessage>> messagesForCompression(
    List<ChatMessage> messages, {
    bool includeAttachmentsAndTools = true,
  }) async {
    if (!includeAttachmentsAndTools) return messages;
    final prompts = await _repo.getMessagePrompts(
      messages
          .where(
            (m) =>
                m.role == 'user' &&
                m.parts.any((p) => p is ImagePart || p is FilePart),
          )
          .map((m) => m.id),
    );
    return [
      for (final message in messages)
        (() {
          final frozen = prompts[message.id];
          var body = message.content;
          if (frozen != null) {
            body = frozen.carriesMemorySnapshot
                ? MemoryBlockBuilder.splitInjectedPrefix(
                        frozen.payload,
                      )?.rest ??
                      body
                : frozen.payload;
          }
          final buffer = StringBuffer(LogPayloadElider.elideDataUris(body));
          for (final part in message.parts) {
            if (part is ToolCallPart) {
              try {
                final tool = jsonDecode(part.payloadJson);
                if (tool is! Map) continue;
                final result = toolResultContentForModel(
                  (tool['content'] ?? '').toString(),
                );
                buffer.write('\n[Tool: ${tool['name'] ?? 'unknown'}]\n');
                if (tool['arguments'] != null) {
                  buffer.write(
                    truncateHeadTailUtf16Safe(
                      LogPayloadElider.elide(jsonEncode(tool['arguments'])),
                      2000,
                      marker: '\n[…truncated…]\n',
                    ),
                  );
                  buffer.write('\n');
                }
                buffer.write(
                  truncateHeadTailUtf16Safe(
                    LogPayloadElider.elide(result),
                    8000,
                    marker: '\n[…truncated…]\n',
                  ),
                );
              } on FormatException {
                buffer.write('\n[Unreadable tool record]');
              }
            } else if (part is FilePart) {
              buffer.write(
                '\n[Attachment: ${part.name}; only available text above is included; binary content was not reread]',
              );
            } else if (part is ImagePart) {
              buffer.write(
                '\n[Image attachment; image content not summarized]',
              );
            }
          }
          return message.copyWith(content: buffer.toString());
        })(),
    ];
  }

  Future<void> clearConversationContext(String conversationId) =>
      contextCompression.runContextChange(conversationId, () async {
        final snapshot = await loadContextSnapshot(conversationId);
        if (snapshot.messages.isEmpty) return;
        final effective = ContextHistory.resolve(
          snapshot.messages,
          ContextHistory.applicable(snapshot.operations, snapshot.messages),
        );
        if (effective.isEmpty) return;
        final tail = ContextHistory.group(snapshot.messages.last);
        await appendContextOperation(
          conversationId,
          ContextOperation(
            id: const Uuid().v4(),
            kind: ContextOperationKind.clear,
            anchorGroupId: tail,
            appliedAfterGroupId: tail,
            sourceGroups: snapshot.messages.map(ContextHistory.group).toList(),
            dependencies: const [],
            createdAt: DateTime.now(),
          ),
          expectedFingerprint: snapshot.fingerprint,
        );
      });

  /// Creates a new conversation seeded with [operation]'s summary followed by
  /// the retained messages. The source conversation is not switched or changed.
  Future<Conversation> createCompressedConversation(
    String conversationId,
    ContextOperation operation, {
    required String expectedFingerprint,
    required List<ChatMessage> retained,
  }) async {
    final before = await loadContextSnapshot(conversationId);
    if (before.fingerprint != expectedFingerprint) {
      throw StateError('context_changed');
    }
    final source = getConversation(conversationId);
    if (source == null) throw StateError('conversation_not_found');
    final seed = <ChatMessage>[
      ChatMessage(
        role: 'user',
        content: operation.summary,
        conversationId: conversationId,
      ),
      for (final message in retained)
        ContextOperation.isSummary(message)
            ? ChatMessage(
                role: 'user',
                content: message.content,
                conversationId: conversationId,
              )
            : message,
    ];
    final created = await forkConversationFromMessages(
      title: source.title,
      assistantId: source.assistantId,
      sourceMessages: seed,
      activate: false,
    );
    if (source.chatModelProvider != null || source.chatModelId != null) {
      await setConversationModel(
        created.id,
        providerKey: source.chatModelProvider,
        modelId: source.chatModelId,
      );
    }
    if (source.mcpServerIds.isNotEmpty) {
      await setConversationMcpServers(created.id, source.mcpServerIds);
    }
    final after = await loadContextSnapshot(conversationId);
    if (after.fingerprint != expectedFingerprint) {
      await deleteConversation(created.id);
      throw StateError('context_changed');
    }
    return created;
  }

  Future<void> appendContextOperation(
    String conversationId,
    ContextOperation operation, {
    required String expectedFingerprint,
  }) async {
    if (!_initialized) return;
    if (_temporaryConversationIds.contains(conversationId) ||
        _draftConversations.containsKey(conversationId)) {
      final snapshot = await loadContextSnapshot(conversationId);
      if (snapshot.fingerprint != expectedFingerprint) {
        throw StateError('context_changed');
      }
      _contextOperations[conversationId] = [...snapshot.operations, operation];
    } else {
      final operations = await _repo.appendContextOperation(
        conversationId,
        operation,
        expectedFingerprint: expectedFingerprint,
      );
      _contextOperations[conversationId] = operations;
    }
    await loadContextOperations(conversationId, refresh: true);
    _notifyContextChanged(conversationId);
  }

  Future<void> changeContextOperation(
    String conversationId,
    String operationId, {
    String? summary,
    required bool includeDependents,
    required String expectedState,
  }) async {
    if (!_initialized) return;
    if (_temporaryConversationIds.contains(conversationId) ||
        _draftConversations.containsKey(conversationId)) {
      final operations = contextOperationsFor(conversationId);
      if (ContextHistory.operationsFingerprint(operations) != expectedState) {
        throw StateError('context_changed');
      }
      final affected = ContextHistory.affectedOperations(
        operations,
        operationIds: {operationId},
      );
      if (!includeDependents && affected.length > 1) {
        throw StateError('context_dependents');
      }
      _contextOperations[conversationId] = [
        for (final op in operations)
          if (op.id == operationId && summary != null)
            op.copyWith(summary: summary)
          else if (affected.contains(op.id))
            op.copyWith(revoked: true)
          else
            op,
      ];
    } else {
      final operations = await _repo.changeContextOperation(
        conversationId,
        operationId,
        summary: summary,
        includeDependents: includeDependents,
        expectedState: expectedState,
      );
      _contextOperations[conversationId] = operations;
    }
    await loadContextOperations(conversationId, refresh: true);
    _notifyContextChanged(conversationId);
  }


  Future<void> restoreContextOperations(
    String conversationId,
    List<ContextOperation> operations, {
    required String expectedFingerprint,
  }) async {
    if (!_initialized) return;
    if (_temporaryConversationIds.contains(conversationId) ||
        _draftConversations.containsKey(conversationId)) {
      final snapshot = await loadContextSnapshot(conversationId);
      if (snapshot.fingerprint != expectedFingerprint) {
        throw StateError('context_changed');
      }
      _contextOperations[conversationId] = List<ContextOperation>.of(
        operations,
      );
    } else {
      await _repo.restoreContextOperations(
        conversationId,
        operations,
        expectedFingerprint: expectedFingerprint,
      );
    }
    await loadContextOperations(conversationId, refresh: true);
    _notifyContextChanged(conversationId);
  }
}
