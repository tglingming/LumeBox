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
}
