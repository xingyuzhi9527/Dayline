# sherpa-onnx 模型选型参考

## 模型家族概览

sherpa-onnx 支持两类 ASR 模型：

| 家族 | 识别方式 | 典型用途 |
|------|---------|---------|
| SenseVoice | 非流式 OfflineRecognizer | 整体录音后识别，输出 emotion/event 标签 |
| Zipformer | 流式 OnlineRecognizer | 实时 partial 结果，边说边出字 |
| Paraformer | 非流式 | 中文优化，类似 SenseVoice 但无情感标签 |

## SenseVoice vs Zipformer 详细对比

| 维度 | SenseVoice Small | Zipformer Small Bilingual |
|------|------------------|--------------------------|
| 模型体积 | ~72 MB (int8) | ~458 MB (int8 tar，解压后更大) |
| 中文精度 | 纯中文训练，精度高 | 中英共享容量，中文被稀释 |
| 语言支持 | 中文为主（auto 自动检测） | 中英双语 |
| 识别模式 | 非流式（整体输入 → 整体输出） | 流式（逐帧输入 → partial + final） |
| 额外输出 | emotion（情感标签）、event（事件标签） | 无 |
| 推荐场景 | 中文短句、语音备忘录、生活记录 | 中英混合场景、需要 partial 进度反馈 |
| 配置复杂度 | 低（OfflineRecognizer，一次性解码） | 高（OnlineRecognizer + VAD + endpoint） |

## 实战选型决策树

```
需要实时 partial 结果显示？
  ├── 是 → Zipformer（流式 OnlineRecognizer）
  │   └── 必须配 Silero VAD + endpoint 参数
  └── 否 → 需要情感/事件标签？
            ├── 是 → SenseVoice
            └── 否 → SenseVoice 或 Paraformer
                      └── 看体积/精度需求
```

## 已验证的模型

### SenseVoice Small Chinese (`multi-zh-hans-2023-12-12`)

- 体积：int8 量化后 ~72MB
- 格式：`sense_voice` modelType
- 已验证效果：中文短句识别速度和准确率均优于 bilingual Zipformer
- 注意：释放前需 `recognizer.free()` 防止 native 内存泄漏

```dart
sherpa.OfflineRecognizer(
  sherpa.OfflineRecognizerConfig(
    model: sherpa.OfflineModelConfig(
      senseVoice: sherpa.OfflineSenseVoiceModelConfig(
        model: 'model.int8.onnx',
        language: 'auto',
        useInverseTextNormalization: true,
      ),
      tokens: 'tokens.txt',
      numThreads: 4,
      provider: 'xnnpack',
      modelType: 'sense_voice',
      debug: false,
    ),
  ),
)
```

### Zipformer Small Bilingual (`2023-02-16`)

- 体积：int8 tar ~458MB
- 格式：`modelType: ''`（空字符串，不是 `'zipformer2'`）
- 已知问题：
  - `modelType: 'zipformer2'` 导致 `query_head_dims does not exist in metadata` 崩溃
  - bilingual 容量稀释导致中文短语准确率不稳定
  - 尾部词确认慢（"分钟"需等较久）
- 如使用需配 `modified_beam_search` + hotwords
- 建议：纯中文场景优先选 SenseVoice

## 模型部署文件清单

无论哪种模型，运行时通常需要：

| 文件 | 用途 |
|------|------|
| `model.int8.onnx` | 主模型（encoder/decoder/joiner 三合一或独立） |
| `tokens.txt` | token 映射表 |
| `bpe.model` / `tokens.txt` | BPE 分词模型（Zipformer 用 bpe.model） |
| `silero_vad.onnx` | VAD 模型（Zipformer 流式场景需要） |
| `life_keywords.txt` | 热词文件（可选，配合 modified_beam_search） |

## 模型更换经验

从 bilingual Zipformer 切换到纯中文 SenseVoice 的过程：
1. 下载新模型 tar.bz2
2. 提取所需文件（model + tokens），生成新的 zip 包
3. 更新 `SttAssetPaths` 中的文件名映射
4. 更新 `SttAssetManager` 默认指向新 zip
5. 重新 build APK 并真机验证
6. 对比 baseline 测试句子的识别效果
7. 清理旧模型文件

真机验证结果：纯中文模型在速度和准确率上均有明显改善。
