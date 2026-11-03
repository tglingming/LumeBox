// Android 电量通道验收：原生侧 lumebox/battery.level 返回 0..100。
//
// 运行方式（设备已连接）：
//   flutter test integration_test/android_battery_channel_test.dart -d <device-id>
//
// 背景（2026-10-31 修复）：阅读器状态栏与视频播放器的电量胶囊走
// MethodChannel('lumebox/battery')，该通道此前只有 iOS 原生实现，
// Android 上 MissingPluginException → 3 秒超时 → 永远显示「—」。
// MainActivity.kt 已补齐 Android 实现（BatteryManager，无需运行时权限）。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('lumebox/battery.level 在 Android 返回有效电量', (tester) async {
    final value = await binding.runAsync(() async =>
        MethodChannel('lumebox/battery')
            .invokeMethod<int>('level')
            .timeout(const Duration(seconds: 5)));
    expect(value, isNotNull, reason: '通道未实现或返回 null（原生 handler 缺失？）');
    expect(value, inInclusiveRange(0, 100), reason: '电量值非法：$value');
  });

  testWidgets('未实现的方法按 notImplemented 报告（通道行为一致性）', (tester) async {
    Object? error;
    await binding.runAsync(() async {
      try {
        await MethodChannel('lumebox/battery')
            .invokeMethod<void>('nonexistent_method')
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        error = e;
      }
    });
    expect(error, isA<MissingPluginException>().having(
      (e) => e.toString(),
      'message',
      contains('nonexistent_method'),
    ));
  });

  testWidgets('lumebox/brightness：isSupported=true，set/current 可用', (
    tester,
  ) async {
    final channel = MethodChannel('lumebox/brightness');
    final supported = await binding.runAsync(
        () => channel.invokeMethod<bool>('isSupported')
            .timeout(const Duration(seconds: 5)));
    expect(supported, isTrue, reason: 'Android 亮度通道应已接入');

    final current = await binding.runAsync(
        () => channel.invokeMethod<double>('current')
            .timeout(const Duration(seconds: 5)));
    expect(current, anyOf(isNull, inInclusiveRange(0.0, 1.0)));

    await binding.runAsync(
        () => channel.invokeMethod<void>('set', {'value': 0.5})
            .timeout(const Duration(seconds: 5)));
    final after = await binding.runAsync(
        () => channel.invokeMethod<double>('current')
            .timeout(const Duration(seconds: 5)));
    expect(after, isNotNull, reason: 'set(0.5) 后 current 应能读到亮度');
  });

  testWidgets('lumebox/privacy：setEnabled 幂等可用', (tester) async {
    final channel = MethodChannel('lumebox/privacy');
    await binding.runAsync(() => channel
        .invokeMethod<void>('setEnabled', {'enabled': true})
        .timeout(const Duration(seconds: 5)));
    await binding.runAsync(() => channel
        .invokeMethod<void>('setEnabled', {'enabled': false})
        .timeout(const Duration(seconds: 5)));
    // 不抛异常即通过：FLAG_SECURE 的可视效果需人工在任务切换卡确认。
  });

  testWidgets('lumebox/webview.allCookies：返回包含元数据的 Cookie 列表', (
    tester,
  ) async {
    final channel = MethodChannel('lumebox/webview');
    final cookies = await binding.runAsync(
        () => channel.invokeListMethod<Object?>(
              'allCookies',
              {'url': 'https://example.com/path'},
            ).timeout(const Duration(seconds: 5)));
    // 模拟器上未必有 Cookie；关键是结构契约（空列表或带七元键的 Map 列表）。
    for (final entry in cookies ?? const []) {
      expect(entry, isA<Map>());
      final map = entry! as Map;
      for (final key in ['name', 'value', 'domain', 'path', 'secure', 'httpOnly']) {
        expect(map.containsKey(key), isTrue, reason: 'Cookie 条目缺 $key：$map');
      }
    }
  });
}
