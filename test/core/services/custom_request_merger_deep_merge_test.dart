import 'package:Kelivo/core/services/custom_request_merger.dart';
import 'package:flutter_test/flutter_test.dart';

/// 自定义请求体的合并语义：**嵌套对象逐键合并，数组/标量整块替换**
/// （少数键互斥的对象例外，见 `_replacedWhole`）。
///
/// 这里的深合并是上游单独做过的修复（`fix(embedding): honor Vertex location and
/// provider-level body`）；本仓库一度退回成浅覆盖（`addAll`），后果是
/// **模型级会把供应商级的同级键整块顶掉**，且不报错。这条测试把它们钉住。
void main() {
  group('mergeBody', () {
    test('模型级只覆盖嵌套对象里的同名键，供应商级的同级键保留', () {
      final merged = CustomRequestMerger.mergeBody(
        providerRows: [
          {
            'key': 'generationConfig',
            'value': '{"temperature":0.7,"topP":0.9}',
          },
        ],
        model: {
          'generationConfig': {'temperature': 0.2},
        },
      );

      expect(merged['generationConfig'], {'temperature': 0.2, 'topP': 0.9});
    });

    test('助手级写的嵌套对象同样参与深合并', () {
      final merged = CustomRequestMerger.mergeBody(
        assistant: {'generationConfig': '{"temperature":0.7,"topP":0.9}'},
        model: {
          'generationConfig': {'temperature': 0.2},
        },
      );

      expect(merged['generationConfig'], {'temperature': 0.2, 'topP': 0.9});
    });

    test('数组整块替换，不与已有数组合并', () {
      final merged = CustomRequestMerger.mergeBody(
        assistant: {'stop': '["a","b"]'},
        model: {
          'stop': ['c'],
        },
      );

      expect(merged['stop'], ['c']);
    });

    test('标量按覆盖处理', () {
      final merged = CustomRequestMerger.mergeBody(
        assistant: {'temperature': '0.9'},
        model: {'temperature': 0.1},
      );

      expect(merged['temperature'], 0.1);
    });
  });

  group('applyBody', () {
    test('嵌套对象逐键合并，生成出来的同级键保留', () {
      final target = <String, dynamic>{
        'generationConfig': {'maxOutputTokens': 4096, 'temperature': 1.0},
      };

      CustomRequestMerger.applyBody(target, {
        'generationConfig': {'temperature': 0.3},
      });

      expect(target['generationConfig'], {
        'maxOutputTokens': 4096,
        'temperature': 0.3,
      });
    });

    test('thinking 整块替换：互斥的键不得被合并进来', () {
      // thinking / reasoning / thinkingConfig 内部的键互斥
      // （`type: disabled` 与 `budget_tokens` 不能同时存在），
      // 逐键合并会被服务端拒绝，所以必须整块替换。
      for (final key in const ['thinking', 'reasoning', 'thinkingConfig']) {
        final target = <String, dynamic>{
          key: {'type': 'enabled', 'budget_tokens': 1000},
        };

        CustomRequestMerger.applyBody(target, {
          key: {'type': 'disabled'},
        });

        expect(target[key], {'type': 'disabled'}, reason: '$key 应整块替换');
      }
    });

    test('多层嵌套也会逐层合并', () {
      final target = <String, dynamic>{
        'a': {
          'b': {'keep': 1, 'override': 1},
        },
      };

      CustomRequestMerger.applyBody(target, {
        'a': {
          'b': {'override': 2},
          'c': 3,
        },
      });

      expect(target['a'], {
        'b': {'keep': 1, 'override': 2},
        'c': 3,
      });
    });
  });
}
