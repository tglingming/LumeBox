// Android 真机 Release 验收：官方源添加 + 页面可打开 + 平台能力口径。
//
// 运行方式（设备已连接）：
//   flutter test integration_test/android_official_sources_test.dart -d <device-id>
//
// 口径说明：
//   图源引擎（QuickJS 沙箱）随 iOS / Android 提供，Windows 保留骨架。
//   2026-10-28 起 Android 全面开放：漫画 / 视频 / REX 官方源可导入、
//   猫源 QuickJS 可用；本测试据此验收（旧 Phase1 iOS-only 口径已废弃）。
//
// 历史修复（2026-10-28）：
//   SourceEngineRegistry.isAvailable / LumeJsEngine.create 曾错接 iOS-only 门、
//   Android 原生库名不匹配（libquickjs_c_bridge_plugin.so），导致 Android
//   全链路不可用；已修复，回归由本文件第 2、3 组用例把守。

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lume_box/app.dart';
import 'package:lume_box/core/js/cat_engines.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/lume_sources.dart';
import 'package:lume_box/features/video/video_source_hub.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('1. 应用启动与页面打开', () {
    testWidgets('App 启动，主导航页签齐全', (tester) async {
      await tester.pumpWidget(const LumeBoxApp());
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // 主导航：漫画 / 视频（内嵌猫源入口）/ 设置。
      // 猫源旧页签已并入 VideoSourceHub（app_shell.dart 页签目录），
      // 不在主导航单独出现。
      for (final label in ['漫画', '视频', '设置']) {
        expect(find.text(label), findsWidgets, reason: '缺少页签：$label');
      }
    });

    testWidgets('逐个切换板块页签，视频聚合页渲染无异常', (tester) async {
      await tester.pumpWidget(const LumeBoxApp());
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // 视频页（VideoSourceHub：本地视频 + 猫源/网页源选择的聚合页）。
      await tester.tap(find.text('视频').first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byType(VideoSourceHub), findsOneWidget,
          reason: '视频页未渲染出 VideoSourceHub');

      // 漫画 / 设置页往返无异常。
      await tester.tap(find.text('漫画').first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await tester.tap(find.text('设置').first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });
  });

  group('2. 平台能力口径（Android）', () {
    test('视频/漫画图源运行时必须为可用（Android 已开放）', () {
      expect(LumeSources.runtimeAvailableFor(Section.video), isTrue);
      expect(LumeSources.runtimeAvailableFor(Section.comic), isTrue);
    });

    test('猫源运行时在 Android 上必须可用', () {
      expect(CatEngines.available, isTrue, reason: 'Android 猫源引擎未就绪');
    });

    testWidgets('真实链路：导入内置猫源脚本成功（QuickJS 引擎可用）',
        (tester) async {
      // 用 catvod 桥接薄壳做导入验收：脚本语法、契约方法、元信息校验
      // 全部走真实 QuickJS 引擎 + 原生库。导入不要求桥接服务在线
      // （地址运行时才读），导入成功即证明 Android 上猫源引擎链路可用。
      final script = await binding.runAsync(() => rootBundle
          .loadString('assets/test_sources/catvod_bridge_source.js'));

      final result = await binding.runAsync(
          () => LumeSources.importScript(Section.cat, script!));
      expect(result!.isSuccess, isTrue,
          reason: '猫源导入失败：${result.message}');
      expect(result.descriptor!.id, 'catvod-bridge');
    });
  });

  group('3. 官方源添加行为', () {
    testWidgets('向视频板块导入 REX 官方演示源 → 成功', (tester) async {
      final script = await binding.runAsync(
          () => rootBundle.loadString('assets/rex/lumebox_demo.js'));

      final result = await binding
          .runAsync(() => LumeSources.importScript(Section.video, script!));
      expect(result!.isSuccess, isTrue,
          reason: 'REX 演示源导入失败：${result.message}');
      // REX 源的库内 id 由内容哈希生成（rex_ 前缀），与 WidgetMetadata.id
      // （lumebox.rex.workflow.demo）不是同一个口径。
      expect(result.descriptor!.id, startsWith('rex_'));
    });

    testWidgets('跨板块导入被拒绝（源声明归属视频，导入漫画 → 优雅拒绝）',
        (tester) async {
      final script = await binding.runAsync(
          () => rootBundle.loadString('assets/rex/lumebox_demo.js'));

      final result = await binding
          .runAsync(() => LumeSources.importScript(Section.comic, script!));
      expect(result!.isSuccess, isFalse);
      expect(result.message, contains('跨板块'),
          reason: '应给出跨板块拒绝原因，实际：${result.message}');
    });

    testWidgets('官方订阅 URL 可达性（网络冒烟）', (tester) async {
      // 不真正走 UI 订阅流程（Android 不可导入），只验证官方源清单网络可达，
      // 便于区分「网络问题」与「平台限制」。
      final status = await binding.runAsync(() async {
        final client = HttpClient();
        try {
          final req = await client.getUrl(Uri.parse(
              'https://raw.githubusercontent.com/teng662858/LumeBox-Sources/main/subscriptions/all.json'));
          final resp = await req.close().timeout(const Duration(seconds: 15));
          return resp.statusCode;
        } finally {
          client.close();
        }
      });
      expect(status, 200, reason: '官方订阅清单不可达（状态码 $status）');
    });
  });
}
