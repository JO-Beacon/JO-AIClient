import 'package:Kelivo/core/models/world_book.dart';
import 'package:Kelivo/features/world_book/utils/world_book_import.dart';
import 'package:flutter_test/flutter_test.dart';

/// SillyTavern（酒馆）的世界书写成「键为序号的对象」，并且支持一大堆本仓库
/// 没有的规则（宏、正则、时效、概率、筛选……）。
/// 这里的底线是：**看不懂的规则一律不要把条目打开**——宁可停用让用户自己看，
/// 也不能让它在聊天时悄悄多注入一段不该注入的内容。
Map<String, dynamic> _stEntry({
  Object? key = const ['dragon'],
  String content = 'CONTENT',
  Object? position,
  Object? depth,
  Object? role,
  Object? order,
  Object? constant,
  Object? disable,
  Object? comment,
  Object? uid,
  Object? scanDepth,
  Map<String, Object?> extra = const {},
}) => {
  'key': key,
  'content': content,
  if (scanDepth != null) 'scanDepth': scanDepth,
  if (position != null) 'position': position,
  if (depth != null) 'depth': depth,
  if (role != null) 'role': role,
  if (order != null) 'order': order,
  if (constant != null) 'constant': constant,
  if (disable != null) 'disable': disable,
  if (comment != null) 'comment': comment,
  if (uid != null) 'uid': uid,
  ...extra,
};

WorldBookImportResult _parse(
  Map<String, Object?> entries, {
  String fileName = 'tavern-book.json',
}) {
  final result = parseWorldBookImport({
    'entries': entries,
    'name': '酒馆书',
  }, fileName: fileName);
  expect(result, isNotNull);
  return result!;
}

WorldBookEntry _only(WorldBookImportResult result) {
  expect(result.book.entries, hasLength(1));
  return result.book.entries.single;
}

void main() {
  group('Kelivo / RikkaHub 导出', () {
    test('entries 是数组时按原样读入，id 与启用状态都保留', () {
      final result = parseWorldBookImport({
        'data': {
          'id': 'book-1',
          'name': 'My book',
          'description': 'desc',
          'entries': [
            {
              'id': 'e1',
              'name': 'Entry',
              'content': 'HELLO',
              'enabled': false,
              'priority': 5,
              'keywords': ['dragon'],
            },
          ],
        },
      }, fileName: 'ignored.json');

      expect(result, isNotNull);
      expect(result!.unsupportedEntryCount, 0);
      expect(result.book.id, 'book-1');
      expect(result.book.name, 'My book');
      expect(result.book.entries.single.id, 'e1');
      expect(result.book.entries.single.enabled, isFalse);
      expect(result.book.entries.single.priority, 5);
    });

    test('数组里混入非对象就整体判为无法识别', () {
      expect(
        parseWorldBookImport({
          'entries': [
            {'content': 'ok'},
            'not-a-map',
          ],
        }, fileName: 'x.json'),
        isNull,
      );
    });
  });

  group('SillyTavern 世界书', () {
    test('书名缺失时用文件名', () {
      final result = parseWorldBookImport({
        'name': '   ',
        'entries': {'0': _stEntry()},
      }, fileName: r'C:\backup\My Tavern Book.JSON');
      expect(result!.book.name, 'My Tavern Book');
    });

    test('位置与角色按支持的那几种映射', () {
      final result = _parse({
        '0': _stEntry(position: 0, uid: 'before'),
        '1': _stEntry(position: 1, uid: 'after'),
        '2': _stEntry(position: 4, depth: 3, role: 2, uid: 'depth'),
        '3': _stEntry(position: 4, depth: 5, role: 1, uid: 'user'),
      });
      final byId = {for (final e in result.book.entries) e.id: e};
      expect(
        byId['before']!.position,
        WorldBookInjectionPosition.beforeSystemPrompt,
      );
      expect(
        byId['after']!.position,
        WorldBookInjectionPosition.afterSystemPrompt,
      );
      expect(byId['depth']!.position, WorldBookInjectionPosition.atDepth);
      expect(byId['depth']!.role, WorldBookInjectionRole.assistant);
      expect(byId['depth']!.injectDepth, 3);
      expect(byId['user']!.role, WorldBookInjectionRole.user);
      expect(result.unsupportedEntryCount, 0);
    });

    test('认不出的插入位置会保留内容但停用', () {
      final result = _parse({
        '0': _stEntry(position: 2, content: 'UNSUPPORTED POSITION'),
      });
      final entry = _only(result);
      expect(entry.enabled, isFalse);
      expect(entry.content, 'UNSUPPORTED POSITION');
      expect(result.unsupportedEntryCount, 1);
    });

    test('同深度混用不同角色时两条都停下等人工确认', () {
      final result = _parse({
        '0': _stEntry(position: 4, depth: 2, role: 1),
        '1': _stEntry(position: 4, depth: 2, role: 2),
      });
      expect(result.book.entries.map((e) => e.enabled), [false, false]);
      expect(result.unsupportedEntryCount, 2);
    });

    test('用户自己关掉的条目不算「不支持的条目」', () {
      final result = _parse({'0': _stEntry(disable: true, content: 'OFF')});
      expect(_only(result).enabled, isFalse);
      expect(result.unsupportedEntryCount, 0);
    });

    test('顺序与顺序相反的优先级：ST 的 order 越大越靠后', () {
      final result = _parse({
        '0': _stEntry(order: 250, uid: 'later'),
        '1': _stEntry(order: 100, uid: 'earlier'),
      });
      final byId = {for (final e in result.book.entries) e.id: e};
      expect(byId['earlier']!.priority, -100);
      expect(byId['later']!.priority, -250);
      expect(byId['earlier']!.priority, greaterThan(byId['later']!.priority));
    });

    test('名字优先用备注，没有备注时用第一个关键词', () {
      final withComment = _parse({
        '0': _stEntry(comment: '备注名', key: ['dragon', 'wyrm']),
      });
      expect(_only(withComment).name, '备注名');

      final withoutComment = _parse({
        '0': _stEntry(key: ['dragon', 'wyrm']),
      });
      expect(_only(withoutComment).name, 'dragon');

      // 没有备注也没有关键词时不能崩，只是没有名字。
      final neither = _parse({'0': _stEntry(key: const <String>[])});
      expect(_only(neither).name, isEmpty);
      expect(_only(neither).enabled, isTrue);
    });

    test('关键词或正文里出现宏时停用（含常驻条目）', () {
      final macroInKey = _parse({
        '0': _stEntry(key: ['{{getvar::place}}']),
      });
      expect(_only(macroInKey).enabled, isFalse);

      final macroInContent = _parse({
        '0': _stEntry(constant: true, content: '位置是 {{getvar::place}}'),
      });
      expect(_only(macroInContent).enabled, isFalse);
      expect(macroInContent.unsupportedEntryCount, 1);
    });

    test('正则关键词留有原文但停用，写坏的正则仍按字面量使用', () {
      final valid = _parse({
        '0': _stEntry(key: [r'/\bdragon\b/i']),
      });
      expect(_only(valid).enabled, isFalse, reason: '正则匹配口径与酒馆不一致');
      expect(_only(valid).keywords, [r'/\bdragon\b/i']);

      final broken = _parse({
        '0': _stEntry(key: ['/([unclosed/']),
      });
      expect(_only(broken).enabled, isTrue, reason: '酒馆也把它当普通关键词');
      expect(_only(broken).keywords, ['/([unclosed/']);
    });

    test('时效、概率、分组、触发器等规则一律停用', () {
      for (final extra in <Map<String, Object?>>[
        {'sticky': 2},
        {'cooldown': 3},
        {'delay': 20000},
        {'useProbability': true, 'probability': 50},
        {'group': 'g'},
        {'automationId': 'a'},
        {
          'triggers': ['x'],
        },
        {'delayUntilRecursion': 1},
        {
          'characterFilter': {
            'names': ['Alice'],
          },
        },
        {'matchWholeWords': true},
        {'vectorized': true},
      ]) {
        final result = _parse({'0': _stEntry(extra: extra)});
        expect(_only(result).enabled, isFalse, reason: '这些规则本仓库不认：$extra');
        expect(result.unsupportedEntryCount, 1, reason: '$extra');
      }
    });

    test('在范围内的延迟是可用的，不该被当成不支持', () {
      final result = _parse({
        '0': _stEntry(content: 'DELAYED', extra: {'delay': 5}),
      });
      expect(_only(result).enabled, isTrue);
      expect(_only(result).delay, 5);
      expect(result.unsupportedEntryCount, 0);
    });

    test('常驻条目不因为关键词与扫描深度被停用，但正文含宏仍会停用', () {
      final result = _parse({
        '0': _stEntry(constant: true, key: const <String>[], scanDepth: 500),
      });
      expect(_only(result).enabled, isTrue);
      expect(result.unsupportedEntryCount, 0);
    });

    test('非恒定条目遇到越界的扫描深度会停用', () {
      final result = _parse({'0': _stEntry(scanDepth: 0)});
      expect(_only(result).enabled, isFalse);
      expect(_only(result).scanDepth, 1, reason: '读回来时至少要落在可用区间');
    });

    test('次级关键词只在「非常驻 + 选择性匹配」时才判为不支持', () {
      final selective = _parse({
        '0': _stEntry(
          extra: {
            'keysecondary': ['other'],
          },
        ),
      });
      expect(_only(selective).enabled, isFalse);

      final constant = _parse({
        '0': _stEntry(
          constant: true,
          extra: {
            'keysecondary': ['other'],
          },
        ),
      });
      expect(_only(constant).enabled, isTrue);
    });

    test('结构不对时返回空，不抛异常', () {
      expect(parseWorldBookImport('nope', fileName: 'x.json'), isNull);
      expect(parseWorldBookImport({'entries': 5}, fileName: 'x.json'), isNull);
      expect(
        parseWorldBookImport({
          'entries': {'0': 'not-a-map'},
        }, fileName: 'x.json'),
        isNull,
      );
      expect(
        parseWorldBookImport({
          'entries': {'0': _stEntry(content: '')..['content'] = 5},
        }, fileName: 'x.json'),
        isNull,
      );
      expect(
        parseWorldBookImport({
          'entries': {'0': _stEntry(key: 'dragon')},
        }, fileName: 'x.json'),
        isNull,
      );
    });
  });

  group('导入后的编号整理', () {
    test('空编号与重复编号会被换成新编号，书本身编号冲突也换', () {
      final book = WorldBook(
        id: 'existing',
        entries: const [
          WorldBookEntry(id: '', content: 'A'),
          WorldBookEntry(id: 'dup', content: 'B'),
          WorldBookEntry(id: 'dup', content: 'C'),
        ],
      );
      final normalized = normalizeImportedWorldBook(
        book,
        existingBookIds: const {'existing'},
      );
      expect(normalized.id, isNotEmpty);
      expect(normalized.id, isNot('existing'));
      final ids = normalized.entries.map((e) => e.id).toList();
      expect(ids.toSet(), hasLength(3));
      expect(ids, isNot(contains('')));
      // 内容与顺序不受影响。
      expect(normalized.entries.map((e) => e.content), ['A', 'B', 'C']);
    });

    test('编号不冲突时原样保留', () {
      final normalized = normalizeImportedWorldBook(
        const WorldBook(
          id: 'keep',
          entries: [WorldBookEntry(id: 'e1', content: 'A')],
        ),
        existingBookIds: const {},
      );
      expect(normalized.id, 'keep');
      expect(normalized.entries.single.id, 'e1');
    });
  });
}
