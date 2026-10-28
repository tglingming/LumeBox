// Android 播放链路验收：MPV 内核可用 + 真实打开公网测试流。
//
// 运行方式（设备已连接）：
//   flutter test integration_test/android_playback_test.dart -d <device-id>
//
// 背景（2026-10-28 修复）：播放器工厂原来只认 iOS，Android 上无任何可用内核，
// 用户实际播放时报 “video player had error … Source error”（ExoPlayer 链路）。
// 修复后 Android 提供 MPV（libmpv 软解兜底）。本测试用公网 H.264 测试流
// 真实打开一次，验证内核创建、媒体加载与状态推进。

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lume_box/core/player/abstract_player.dart';
import 'package:lume_box/core/player/player_factory.dart';
import 'package:lume_box/core/player/player_settings.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('1. 播放器平台口径（Android）', () {
    test('视频板块播放器必须有可用内核', () {
      expect(PlayerFactory.isSupported, isTrue,
          reason: 'Android 应提供 MPV 内核');
    });

    test('MPV 可用，AVPlayer/MDK 不可用（平台矩阵）', () {
      expect(PlayerFactory.isAvailable(PlayerKernel.mpv), isTrue);
      expect(PlayerFactory.isAvailable(PlayerKernel.avplayer), isFalse);
      expect(PlayerFactory.isAvailable(PlayerKernel.mdk), isFalse);
    });
  });

  group('2. 真实播放（本地 H.264 样片）', () {
    testWidgets('诊断：原生 media_kit 直接打开本地文件', (tester) async {
      // 绕过 App 引擎层，直测 media_kit：如果这里也挂，问题在 media_kit
      // 与本机模拟器环境的组合；如果这里秒开，问题在 App 引擎的写入链。
      final result = await binding.runAsync(() async {
        MediaKit.ensureInitialized();
        final player = Player();
        try {
          final watch = Stopwatch()..start();
          await player
              .open(Media('/sdcard/bbb_test.mp4'), play: false)
              .timeout(const Duration(seconds: 15));
          return 'ok in ${watch.elapsedMilliseconds}ms';
        } on TimeoutException {
          return 'TIMEOUT(15s)';
        } catch (error) {
          return 'error: $error';
        } finally {
          player.dispose();
        }
      });
      expect(result, startsWith('ok'),
          reason: '原生 media_kit 打开本地文件失败：$result');
    });

    testWidgets('诊断：原生 media_kit + VideoController 打开本地文件', (tester) async {
      // 对照实验：App 引擎构造时会同时建 VideoController（视频纹理），
      // open() 会等视频控制器初始化。若本用例超时而上一用例通过，
      // 即证明挂点在纹理初始化（模拟器环境），而非媒体装载本身。
      final result = await binding.runAsync(() async {
        MediaKit.ensureInitialized();
        final player = Player();
        final video = VideoController(player);
        try {
          final watch = Stopwatch()..start();
          await player
              .open(Media('/sdcard/bbb_test.mp4'), play: false)
              .timeout(const Duration(seconds: 15));
          return 'ok in ${watch.elapsedMilliseconds}ms';
        } on TimeoutException {
          return 'TIMEOUT(15s)';
        } catch (error) {
          return 'error: $error';
        } finally {
          // media_kit_video 2.0.1 的 VideoController 没有 dispose；
          // player.dispose 会连带释放纹理资源。
          player.dispose();
        }
      });
      expect(result, startsWith('ok'),
          reason: '带 VideoController 打开本地文件失败：$result');
    });

    testWidgets('MPV 内核创建 → 打开本地样片 → 状态推进无错误', (tester) async {
      final player = await binding.runAsync(
          () async => PlayerFactory.create(kernel: PlayerKernel.mpv));
      expect(player, isNotNull, reason: 'MPV 内核创建失败（media_kit 初始化？）');
      addTearDown(() async => player!.dispose());

      // 优先本地文件（adb push 的 5.5MB H.264 样片）：排除模拟器外网变量，
      // 单独验证 media_kit 在 Android 的装载/解码/状态链路。
      // 本地文件缺失时退回 mux.dev 公开 HLS（与 REX 演示源同一测试流）。
      final local = File('/sdcard/bbb_test.mp4');
      final uri = local.existsSync()
          ? Uri.file(local.path)
          : Uri.parse('https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8');

      Object? loadError;
      await binding.runAsync(() async {
        try {
          await player!
              .load(PlayerMedia(uri: uri))
              .timeout(const Duration(seconds: 45));
          await player.play();
        } catch (error) {
          loadError = error;
        }
      });
      expect(loadError, isNull, reason: '加载/起播异常：$loadError');

      // 轮询快照 60 秒：拿到时长或进入播放即成功；快照报错即失败。
      Object? snapshotError;
      var reached = false;
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(deadline) && !reached) {
        final snapshot =
            await binding.runAsync(() async => player!.snapshot.value);
        if (snapshot == null) continue;
        if (snapshot.error != null) {
          snapshotError = snapshot.error;
          break;
        }
        reached = snapshot.duration > Duration.zero && !snapshot.buffering ||
            snapshot.playing;
        if (!reached) await Future<void>.delayed(const Duration(seconds: 1));
      }
      expect(snapshotError, isNull,
          reason: '播放快照报错（即用户看到的 source error 一类问题）');
      expect(reached, isTrue,
          reason: '60 秒内既没拿到时长也没起播（模拟器软解过慢可放宽）');
    });
  });
}