# Rich Haptics 原生震动精修设计

- 日期：2026-07-11
- 分支：rc0.4
- 范围：把 `Haptics` 的 7 个静态方法从 Flutter 预设封装改为 Android 原生 `VibrationEffect`，修正 `error()` 与 `warning()` 退化等价的问题，让每个方法有独立触感。不改动方法签名与 64 个调用点（跨 35 文件）。

## 背景与问题

`lib/core/haptics/haptics.dart` 当前 7 个方法全部走 `HapticFeedback.*`：

| 方法 | 现状 |
|---|---|
| `selection()` | `HapticFeedback.selectionClick()` |
| `light()` | `HapticFeedback.lightImpact()` |
| `medium()` | `HapticFeedback.mediumImpact()` |
| `heavy()` | `HapticFeedback.heavyImpact()` |
| `error()` | `HapticFeedback.vibrate()` |
| `warning()` | `HapticFeedback.vibrate()` |
| `success()` | `HapticFeedback.mediumImpact()` |

两个核心问题：

1. **`error()` 与 `warning()` 完全等价** —— 都退化为同一个 `vibrate()`，丢失语义区分。
2. **全预设、无波形控制** —— `HapticFeedback.*` 是 Flutter 对系统 API 的薄封装，只能用预设模式，无法用 `VibrationEffect.createWaveform` / `createPredefined` 给「匹配成功」「卡片滑出」「计划生成完成」等关键时刻配定制波形。

minSdk = 31（见 [android/app/build.gradle.kts:36](android/app/build.gradle.kts#L36)），`createPredefined`（API 29+）与 `createWaveform`（API 26+）均无需 `Build.VERSION` 守卫。

## 总体策略

**薄替换，不动 API**：7 个方法名与 `static void` 签名保持不变，52 个调用点零改动。Android 上改走原生 MethodChannel + `VibrationEffect`；iOS / web / 通道异常时回退到现有 `HapticFeedback.*`，保证不回归。

技术选型：

- 新增 MethodChannel `top.schonavi.app/haptics`，与现有 `top.schonavi.app/preparation_reminders` 同前缀（见 [MainActivity.kt:24](android/app/src/main/kotlin/com/example/scho_navi/MainActivity.kt#L24)）。
- Kotlin handler 独立成 `HapticsChannel.kt`，沿用 `NotificationActionCoordinator.kt` 的「每通道一文件」惯例，不让 [MainActivity.kt](android/app/src/main/kotlin/com/example/scho_navi/MainActivity.kt) 继续膨胀（已 333 行）。
- 不引入第三方震动包（如 `vibration`），符合 CLAUDE.md「不引入新库需批准」约束。
- 每次调用按平台路由，不设全局 `isSupported` 标志 —— 保持 `static void` 干净，调用点无需读能力位。

## 改动

### 3.1 Dart 层 —— `lib/core/haptics/haptics.dart`

7 个方法名与 `void` 签名不变。新增私有通道与一个统一受保护的 `_invoke` helper：

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class Haptics {
  Haptics._();

  static const _channel = MethodChannel('top.schonavi.app/haptics');

  static void selection() =>
      _invoke('selection', HapticFeedback.selectionClick);
  static void light() => _invoke('light', HapticFeedback.lightImpact);
  static void medium() => _invoke('medium', HapticFeedback.mediumImpact);
  static void heavy() => _invoke('heavy', HapticFeedback.heavyImpact);
  static void error() => _invoke('error', HapticFeedback.vibrate);
  static void warning() => _invoke('warning', HapticFeedback.vibrate);
  static void success() => _invoke('success', HapticFeedback.mediumImpact);

  /// Android：走原生 VibrationEffect；其它平台 / 通道异常 → fallback。
  /// 触感失败不应抛到 UI，故 void + 吞异常；debug 下打 log 防静默失效。
  static void _invoke(String method, void Function() fallback) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _channel.invokeMethod<void>(method).catchError((Object _) {
        if (kDebugMode) debugPrint('Haptics $method failed, fallback');
        fallback();
      });
      return;
    }
    fallback();
  }
}
```

要点：

- **路由（决策 C）**：Android → 试原生通道，`PlatformException` / `MissingPluginException` / 任意错误 → `catchError` 跑 `HapticFeedback.*` 回退；iOS / web → 直接 `HapticFeedback.*`，保留今日行为，不回归。
- **`void` + 吞异常**：触感绝不能让按钮 tap 崩溃；`void` 签名与 52 调用点不变。
- **debug-only log**：方法名拼写错 / handler 未注册时，原生触感会静默消失 —— `kDebugMode` 下 `debugPrint` 让开发期能发现，release 不打 log。
- **无全局 `isSupported`**：每次调用自路由，调用点零感知。

### 3.2 Kotlin 层 —— 新文件 `android/app/src/main/kotlin/com/example/scho_navi/HapticsChannel.kt`

```kotlin
package top.schonavi.app

import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object HapticsChannel {
    private const val CHANNEL_NAME = "top.schonavi.app/haptics"

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                val vibrator = flutterEngine.context
                    .getSystemService(Vibrator::class.java)
                if (vibrator == null || !vibrator.hasVibrator()) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "selection" -> vibrator.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK))
                    "light" -> vibrator.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK))
                    "medium" -> vibrator.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_HEAVY_CLICK))
                    "heavy" -> vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 30, 20, 30), -1))
                    "error" -> vibrator.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_DOUBLE_CLICK))
                    "warning" -> vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 40, 30, 40), -1))
                    "success" -> vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 20, 50, 20), -1))
                    else -> { result.notImplemented(); return@setMethodCallHandler }
                }
                result.success(null)
            }
    }
}
```

`MainActivity.configureFlutterEngine` 增一行注册（`cleanUpFlutterEngine` 不必显式清，handler 随 engine 释放，与 `NotificationActionCoordinator` 注册方式对齐）：

```kotlin
HapticsChannel.register(flutterEngine)
```

要点：

- **minSdk=31 无版本守卫**：`createPredefined`（API 29+）/ `createWaveform`（API 26+）均直接可用。
- **`hasVibrator()` 守卫**：无震动器设备静默 no-op，`result.success(null)`。
- **波形 `-1` repeat**：不重复，单次播放。
- **`EFFECT_TICK`/`EFFECT_CLICK`/`EFFECT_HEAVY_CLICK`/`EFFECT_DOUBLE_CLICK`** 为 API 29+ predefined，Q+ 设备原生支持。

### 3.3 效果映射表

| 方法 | 原生效果 | 类型 | 回退 (iOS/web/异常) |
|---|---|---|---|
| `selection` | `EFFECT_TICK` | predefined | `selectionClick` |
| `light` | `EFFECT_CLICK` | predefined | `lightImpact` |
| `medium` | `EFFECT_HEAVY_CLICK` | predefined | `mediumImpact` |
| `heavy` | `[0,30,20,30]` ms | waveform | `heavyImpact` |
| `error` | `EFFECT_DOUBLE_CLICK` | predefined | `vibrate` |
| `warning` | `[0,40,30,40]` ms | waveform | `vibrate` |
| `success` | `[0,20,50,20]` ms | waveform（上升感） | `mediumImpact` |

修正点：

- `error` ≠ `warning`：`EFFECT_DOUBLE_CLICK` vs 自定义波形，语义与触感均区分。
- `success` ≠ `medium`：上升波形 vs `EFFECT_HEAVY_CLICK`，「匹配成功 / 计划生成完成」与普通按钮按压区分。

波形时长为起始调参值，可后续微调。

## 数据流、边界与错误处理

| 边界 | 处理 |
|---|---|
| iOS / web | 直接走 `HapticFeedback.*` 回退，保留今日行为，零回归 |
| Android 通道未注册 / 方法名错 | `catchError` → `HapticFeedback.*` 回退；debug 下 `debugPrint` |
| 无震动器设备 | Kotlin `hasVibrator()` false → no-op，`result.success(null)` |
| `Vibrator` 服务取不到 | Kotlin `vibrator == null` → no-op |
| 调用点（52 处） | 零改动，方法名与 `void` 签名不变 |

风险：

- **`createPredefined` 设备支持差异**：极少数 OEM ROM 可能不实现某个 predefined effect，系统会静默退化为默认震动 —— 不影响功能，最坏只是触感退回预设，可接受。
- **`Vibrator` vs `VibratorManager`**：API 31 上 `Vibrator` 仍可直接 `getSystemService(Vibrator::class.java)`，无需走 API 31 新增的 `VibratorManager`，保持简单。

## 测试与验证

### 单元测试（最小相关优先）

**现有 [test/core/haptics/haptics_test.dart](test/core/haptics/haptics_test.dart)**（1 个测试，断言 `selection` 触发 `SystemChannels.platform` 上的 `HapticFeedback.vibrate`）：

- 默认测试平台（非 Android）路由到 `HapticFeedback.*` 回退，现有断言继续成立 —— **该测试无需改动**。

**新增测试**（同文件追加）：

- mock `top.schonavi.app/haptics` 通道，设 `defaultTargetPlatform = TargetPlatform.android`：
  - 7 个方法各调一次，断言通道收到对应方法名（`selection` / `light` / `medium` / `heavy` / `error` / `warning` / `success`）。
  - 通道抛 `MissingPluginException` → 断言回退到 `HapticFeedback.*`（`SystemChannels.platform` 收到对应 `HapticFeedback.vibrate` + type arg）。
- 平台恢复默认后，断言 iOS/web 路径直接走 `HapticFeedback.*`，不调原生通道。

### 手测清单（触感改动必须手测）

设备：Android 真机（minSdk 31+，即 Android 12+）。

1. `selection`：列表/分段切换 → 极轻 tick。
2. `light`：tile 点按 → 轻 click。
3. `medium`：按钮按压 → 重 click。
4. `heavy`：强确认 → 双段重击 `[0,30,20,30]`。
5. `error`（如生成失败）→ 双击 `EFFECT_DOUBLE_CLICK`，与 `warning` 明显不同。
6. `warning`（如拦截确认）→ 自定义波形 `[0,40,30,40]`，与 `error` 明显不同。
7. `success`（如匹配成功 / 计划生成完成）→ 上升波形 `[0,20,50,20]`，与 `medium` 明显不同。
8. 关闭系统震动（设置 → 声音 → 触感反馈关）→ 无异常、无崩溃。
9. 无震动器设备（若可得）→ 静默 no-op，无崩溃。

### 静态检查

```bash
flutter analyze
dart format --set-exit-if-changed lib test
flutter test test/core/haptics/haptics_test.dart
```

### 不做的事

- 不新增语义方法（`matchSuccess()` / `cardDismissed()` 等）—— YAGNI，现有 7 方法已覆盖场景。
- 不做 iOS 原生触感（`UIFeedbackGenerator`）—— 当前仅 Android 原生化。
- 不引入 `HapticEffect` enum / registry —— 对 7 入口 surface 是过度设计。
- 不改动 52 个调用点。
- 不引入第三方震动包。

### 完成判定

新增 / 既有 haptics 测试全绿、`flutter analyze` 无新增 error/warning、手测清单 1–9 全过 → 视为完成。若本地无法起 Android 真机，明确说明，至少交付单测 + Kotlin 编译通过。
