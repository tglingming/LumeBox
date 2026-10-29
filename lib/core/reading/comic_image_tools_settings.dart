import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum TextTranslationMode { system, ai, fallback }

/// 设备端（系统）翻译的运行时能力判定。
///
/// 系统翻译桥（`lumebox/comicImages` 通道的 `translate`）目前只有 iOS 侧实现
/// （Apple Translation 框架，iOS 18+）。Android 没有系统翻译 API 接入，
/// 一律视为不支持：UI 入口据此隐藏「系统翻译」选项，服务层据此快速失败，
/// 避免每次调用都走到 MissingPluginException 才把 iOS 提示糊给用户。
/// 将来 Android 接入 ML Kit 等设备端方案时，只需改这一处判定。
bool systemTranslationSupported({bool? debugOverride}) =>
    debugOverride ?? Platform.isIOS;

class ComicImageToolsSettings extends ChangeNotifier {
  static final instance = ComicImageToolsSettings();
  static const fileName = 'comic_image_tools.json';

  /// 测试注入点：覆盖 [systemTranslationSupported] 的平台判定，
  /// 宿主单测无需跑在 Android 上也能验证两条门控分支。
  @visibleForTesting
  static bool? debugSystemTranslationSupported;
  bool automatic = false;
  bool upscaleCovers = false;
  bool upscaleVideoPosters = false;
  int concurrency = 1;
  int threshold = 1080;
  int noise = 0;
  String imageStyle = 'anime';
  String target = 'zh-Hans';
  String source = 'auto';
  bool liveTranslation = false;
  bool ai = false;
  bool aiFallback = false;
  /// 读取全局翻译方式；**Android 兼容降级**：
  ///
  /// 设备端翻译仅 iOS 提供（见 [systemTranslationSupported]）。存量配置里
  /// 停在 system 的 Android 用户：已配置 AI 接口 → 直接按 AI 走（联网，
  /// 语义从「本地」变「联网」，但可用）；未配置 → 保持 system，由服务层
  /// 快速失败并给出平台感知的提示，而不是每页抛 MissingPluginException。
  TextTranslationMode get translationMode {
    final mode = ai
        ? TextTranslationMode.ai
        : aiFallback
        ? TextTranslationMode.fallback
        : TextTranslationMode.system;
    final systemSupported =
        debugSystemTranslationSupported ?? systemTranslationSupported();
    if (mode == TextTranslationMode.system &&
        !systemSupported &&
        endpoint.trim().isNotEmpty) {
      return TextTranslationMode.ai;
    }
    return mode;
  }

  /// 写入全局翻译方式。Android 不支持 system：调用方 UI 已不展示该选项，
  /// 这里再做一道兜底——落到 system 的写入按 AI 处理，避免存下一个
  /// 本平台永远走不通的模式。
  set translationMode(TextTranslationMode value) {
    final systemSupported =
        debugSystemTranslationSupported ?? systemTranslationSupported();
    ai = value == TextTranslationMode.ai ||
        (value == TextTranslationMode.system && !systemSupported);
    aiFallback = value == TextTranslationMode.fallback && systemSupported;
  }

  bool serverTranslation = false;
  String imageTranslationEndpoint = '';
  String serverOcr = '48px';
  String serverTranslator = 'chatgpt';
  String endpoint = '';
  String model = '';
  String colorizeEndpoint = '';
  String colorizeProtocol = 'openai';
  String colorizeModel = '';
  String colorizePrompt = defaultColorizePrompt;

  static const String defaultColorizePrompt =
      'Colorize this black-and-white manga page with natural, muted colors. '
      'Keep the original line art, composition and text unchanged.';
  Future<void> _pending = Future.value();

  Future<void> boot() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$fileName');
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return;
      automatic = data['automatic'] == true;
      upscaleCovers = data['upscaleCovers'] == true;
      upscaleVideoPosters = data['upscaleVideoPosters'] == true;
      final rawConcurrency = data['concurrency'];
      concurrency = rawConcurrency is int ? rawConcurrency.clamp(1, 4) : 1;
      imageStyle = data['imageStyle'] == 'photo' ? 'photo' : 'anime';
      threshold = [720, 1080, 1440, 2160].contains(data['threshold'])
          ? data['threshold'] as int
          : 1080;
      noise = [0, 1, 2, 3].contains(data['noise']) ? data['noise'] as int : 0;
      target = languages.containsKey(data['target'])
          ? data['target'] as String
          : 'zh-Hans';
      source = data['source'] == 'auto' || languages.containsKey(data['source'])
          ? data['source'] as String
          : 'auto';
      liveTranslation = data['liveTranslation'] == true;
      ai = data['ai'] == true;
      aiFallback = !ai && data['aiFallback'] == true;
      serverTranslation = data['serverTranslation'] == true;
      imageTranslationEndpoint = '${data['imageTranslationEndpoint'] ?? ''}';
      serverOcr = data['serverOcr'] == 'mocr' ? 'mocr' : '48px';
      serverTranslator =
          [
            'chatgpt',
            'deepl',
            'youdao',
            'baidu',
            'sakura',
          ].contains(data['serverTranslator'])
          ? data['serverTranslator'] as String
          : 'chatgpt';
      endpoint = data['endpoint'] is String ? data['endpoint'] as String : '';
      model = data['model'] is String ? data['model'] as String : '';
      colorizeEndpoint = data['colorizeEndpoint'] is String
          ? data['colorizeEndpoint'] as String
          : '';
      colorizeModel = data['colorizeModel'] is String
          ? data['colorizeModel'] as String
          : '';
      colorizeProtocol = data['colorizeProtocol'] == 'seedream'
          ? 'seedream'
          : 'openai';
      final prompt = data['colorizePrompt'];
      if (prompt is String && prompt.trim().isNotEmpty) {
        colorizePrompt = prompt;
      }
    } catch (_) {
      // Optional preferences must never prevent reading.
    }
    notifyListeners();
  }

  Future<void> save() {
    final text = jsonEncode({
      'automatic': automatic,
      'upscaleCovers': upscaleCovers,
      'upscaleVideoPosters': upscaleVideoPosters,
      'concurrency': concurrency.clamp(1, 4),
      'threshold': threshold,
      'noise': noise,
      'imageStyle': imageStyle,
      'target': target,
      'source': source,
      'liveTranslation': liveTranslation,
      'ai': ai,
      'aiFallback': aiFallback,
      'serverTranslation': serverTranslation,
      'imageTranslationEndpoint': imageTranslationEndpoint,
      'serverOcr': serverOcr,
      'serverTranslator': serverTranslator,
      'endpoint': endpoint,
      'model': model,
      'colorizeEndpoint': colorizeEndpoint,
      'colorizeProtocol': colorizeProtocol,
      'colorizeModel': colorizeModel,
      'colorizePrompt': colorizePrompt,
    });
    notifyListeners();
    _pending = _pending.catchError((Object _) {}).then((_) async {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$fileName');
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(file.path);
    });
    return _pending;
  }

  static const languages = {
    'zh-Hans': '简体中文',
    'zh-Hant': '繁体中文',
    'en': '英语',
    'ja': '日语',
    'ko': '韩语',
    'fr': '法语',
    'de': '德语',
    'es': '西班牙语',
    'ru': '俄语',
    'pt': '葡萄牙语',
    'it': '意大利语',
    'ar': '阿拉伯语',
  };
}
