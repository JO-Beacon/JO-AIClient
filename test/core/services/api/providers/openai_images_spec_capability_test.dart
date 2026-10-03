import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/providers/openai_images.dart';

/// OpenAI Images 的能力判定必须读**模型规格**，不能按模型 id 字符串猜。
///
/// 背景：旧实现按 id 前缀硬编码（`gpt-image-` / `dall-e-` 等）。后果有两个方向：
/// - 中转与自定义供应商里的图片模型，只要 id 不在那份名单里，就**静默失去出图能力**；
/// - 反过来，名字像图片模型但实际是聊天模型的，会被错误地送进出图接口。
///
/// 这里用同一张规格表的两种取值来钉住判定口径：**id 长什么样不参与判定**。
void main() {
  ProviderConfig configWith(String modelId, Map<String, dynamic> spec) {
    return ProviderConfig(
      id: 'openaiImagesSpecTest',
      enabled: true,
      name: 'openaiImagesSpecTest',
      apiKey: 'test-key',
      baseUrl: 'http://127.0.0.1:1',
      providerType: ProviderKind.openai,
      models: [modelId],
      modelOverrides: {modelId: spec},
    );
  }

  const imageSpec = <String, dynamic>{
    'type': 'image',
    'input': ['text', 'image'],
    'output': ['image'],
  };
  const chatSpec = <String, dynamic>{
    'type': 'chat',
    'input': ['text'],
    'output': ['text'],
  };

  test('规格声明为图片模型：id 不认识也走出图接口', () {
    expect(
      shouldUseOpenAIImagesApi(
        configWith('my-relay-drawer-v3', imageSpec),
        'my-relay-drawer-v3',
      ),
      isTrue,
    );
  });

  test('规格声明为聊天模型：id 再像图片模型也不走出图接口', () {
    expect(
      shouldUseOpenAIImagesApi(
        configWith('gpt-image-1', chatSpec),
        'gpt-image-1',
      ),
      isFalse,
    );
  });

  test('规格声明为图片模型且 id 也像：仍走出图接口', () {
    expect(
      shouldUseOpenAIImagesApi(
        configWith('gpt-image-1', imageSpec),
        'gpt-image-1',
      ),
      isTrue,
    );
  });

  test('规格既不是图片也不是聊天（嵌入）：不走出图接口', () {
    const embeddingSpec = <String, dynamic>{
      'type': 'embedding',
      'input': ['text'],
      'output': ['embedding'],
    };
    expect(
      shouldUseOpenAIImagesApi(
        configWith('text-embedding-3-small', embeddingSpec),
        'text-embedding-3-small',
      ),
      isFalse,
    );
  });
}
