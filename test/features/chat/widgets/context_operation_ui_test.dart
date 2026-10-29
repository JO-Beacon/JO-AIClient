import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/context_operation.dart';
import 'package:Kelivo/features/chat/widgets/context_impact_dialog.dart';
import 'package:Kelivo/features/chat/widgets/context_node_divider.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

ContextOperation _operation({
  required String id,
  required ContextOperationKind kind,
  String anchor = 'm1',
  String summary = '',
  String originalSummary = '',
  bool revoked = false,
  List<String> dependencies = const [],
  DateTime? createdAt,
}) => ContextOperation(
  id: id,
  kind: kind,
  anchorGroupId: anchor,
  appliedAfterGroupId: anchor,
  sourceGroups: [anchor],
  dependencies: dependencies,
  createdAt: createdAt ?? DateTime(2026, 1, 1, 12),
  summary: summary,
  originalSummary: originalSummary,
  revoked: revoked,
);

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('clear divider opens on tap and exposes undo', (tester) async {
    var opened = 0;
    var undone = 0;
    await tester.pumpWidget(
      _app(
        ContextOperationDivider(
          operation: _operation(id: 'op-clear', kind: ContextOperationKind.clear),
          onOpen: () => opened++,
          onUndo: () => undone++,
        ),
      ),
    );

    expect(find.text('Clear Context'), findsOneWidget);
    await tester.tap(find.text('Clear Context'));
    expect(opened, 1);

    await tester.tap(find.byKey(const ValueKey('undo-context-op-clear')));
    expect(undone, 1);
  });

  testWidgets('compression divider marks edited summaries', (tester) async {
    await tester.pumpWidget(
      _app(
        ContextOperationDivider(
          operation: _operation(
            id: 'op-compress',
            kind: ContextOperationKind.compress,
            summary: 'edited summary',
            originalSummary: 'original summary',
          ),
          onOpen: () {},
        ),
      ),
    );

    expect(find.text('Context compressed · edited'), findsOneWidget);
    expect(find.byKey(const ValueKey('undo-context-op-compress')), findsNothing);
  });

  testWidgets('revoked divider renders nothing', (tester) async {
    await tester.pumpWidget(
      _app(
        ContextOperationDivider(
          operation: _operation(
            id: 'op-revoked',
            kind: ContextOperationKind.clear,
            revoked: true,
          ),
          onOpen: () {},
        ),
      ),
    );

    expect(find.byType(ContextOperationDivider), findsOneWidget);
    expect(find.text('Clear Context'), findsNothing);
  });

  testWidgets('impact dialog lists affected nodes and token budget', (
    tester,
  ) async {
    final first = _operation(
      id: 'op-1',
      kind: ContextOperationKind.clear,
      createdAt: DateTime(2026, 1, 1, 10),
    );
    final second = _operation(
      id: 'op-2',
      kind: ContextOperationKind.compress,
      anchor: 'm2',
      summary: 'summary',
      originalSummary: 'summary',
      dependencies: const ['op-1'],
      createdAt: DateTime(2026, 1, 1, 11),
    );

    await tester.pumpWidget(
      _app(
        ContextImpactDialog(
          operations: [first, second],
          affectedIds: {'op-1', 'op-2'},
          kind: ContextImpactKind.undo,
          before: (usedTokens: 1200, contextWindow: 4000),
          after: (usedTokens: 400, contextWindow: 4000),
        ),
      ),
    );

    expect(find.text('Undo earlier compression?'), findsOneWidget);
    expect(find.text('Undo 2 nodes'), findsOneWidget);
    expect(find.text('Approx. 1.2k → 400 tokens'), findsOneWidget);
    expect(find.text('Also undone'), findsNWidgets(2));
  });

  testWidgets('impact warning shows when the undo result exceeds the window', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ContextImpactDialog(
          operations: [
            _operation(id: 'op-1', kind: ContextOperationKind.clear),
          ],
          affectedIds: {'op-1'},
          kind: ContextImpactKind.clear,
          before: (usedTokens: 400, contextWindow: 1000),
          after: (usedTokens: 1400, contextWindow: 1000),
        ),
      ),
    );

    expect(
      find.textContaining('Undo may exceed the context limit'),
      findsOneWidget,
    );
  });
}
