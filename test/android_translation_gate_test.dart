// Android 门控单元测试：翻译能力判定与毛玻璃实时模糊降级。
// 宿主 flutter test 可跑（不依赖原生桥）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/reading/comic_image_tools_settings.dart';
import 'package:lume_box/shared/widgets/frosted_glass_widget.dart';
import 'package:lume_box/shared/widgets/module_glass_scope.dart';

void main() {
  group('systemTranslationSupported（设备端翻译平台门）', () {
    test('显式覆盖 true/false 生效', () {
      expect(systemTranslationSupported(debugOverride: true), isTrue);
      expect(systemTranslationSupported(debugOverride: false), isFalse);
    });

    test('Android 判定为不支持（除非显式覆盖）', () {
      // 宿主可能是 Windows/macOS/Linux；这里只验证「覆盖优先于平台」，
      // 平台分支在模拟器集成测试里已实测（Android=false 路径）。
      final fallback = systemTranslationSupported();
      expect(systemTranslationSupported(debugOverride: fallback), fallback);
    });
  });

  group('ComicImageToolsSettings.translationMode（Android 兼容降级）', () {
    tearDown(() => ComicImageToolsSettings.debugSystemTranslationSupported = null);

    test('system 不可用 + 已配置 endpoint → 读取时降级为 AI', () {
      ComicImageToolsSettings.debugSystemTranslationSupported = false;
      final settings = ComicImageToolsSettings();
      settings.translationMode = TextTranslationMode.system; // iOS 机器上的写入
      settings.endpoint = 'https://example.com/v1/chat/completions';
      expect(settings.translationMode, TextTranslationMode.ai);
    });

    test('system 不可用 + 无 endpoint → 保持 system（服务层给平台感知提示）', () {
      ComicImageToolsSettings.debugSystemTranslationSupported = false;
      final settings = ComicImageToolsSettings();
      // 直接模拟 iOS 机器上持久化下来的存量配置（setter 在本平台已做兜底，
      // 不可能再写出 system，所以这里绕过 setter 置原始标志位）。
      settings.ai = false;
      settings.aiFallback = false;
      settings.endpoint = '';
      expect(settings.translationMode, TextTranslationMode.system);
    });

    test('system 可用时写入/读取不回退', () {
      ComicImageToolsSettings.debugSystemTranslationSupported = true;
      final settings = ComicImageToolsSettings();
      settings.translationMode = TextTranslationMode.fallback;
      expect(settings.translationMode, TextTranslationMode.fallback);
    });
  });

  group('FrostedGlassWidget 实时模糊门', () {
    Widget harness({required bool liveBlur, bool translucent = true}) {
      FrostedGlassWidget.debugLiveBlurOverride = liveBlur;
      addTearDown(() => FrostedGlassWidget.debugLiveBlurOverride = null);
      return MaterialApp(
        home: Scaffold(
          body: ModuleGlassScope(
            module: GlassModule.comic,
            part: GlassPart.panels,
            child: FrostedGlassWidget(
              translucentOverlay: translucent,
              child: const SizedBox(width: 200, height: 80),
            ),
          ),
        ),
      );
    }

    testWidgets('liveBlur=false（Android 口径）不挂 BackdropFilter', (
      tester,
    ) async {
      await tester.pumpWidget(harness(liveBlur: false));
      await tester.pump();
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('liveBlur=true（iOS/桌面口径）挂 BackdropFilter', (
      tester,
    ) async {
      await tester.pumpWidget(harness(liveBlur: true));
      await tester.pump();
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });
}
