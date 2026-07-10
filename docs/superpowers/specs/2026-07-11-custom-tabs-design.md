# Chrome Custom Tabs 应用内浏览设计

- 日期：2026-07-11
- 分支：rc0.4
- 范围：把 `LinkLauncher` 的外链打开方式从「跳系统浏览器」改为 Android Custom Tabs 应用内浏览（带底部返回栏、可预热），失败时回退到 `ACTION_VIEW`。`LinkLauncher` 接口与 5 个调用点零改动。`url_launcher` 依赖保留，作为 iOS/web 平台的外跳实现（今日行为不变）。

## 背景与问题

`lib/core/launcher/url_launcher_link_launcher.dart` 当前用 `launchUrl(uri, mode: LaunchMode.externalApplication)` 打开外链 —— 教授主页、竞赛官网、收藏项、首页推荐、chat 内链接均会跳出 app 到系统浏览器，用户脱离应用上下文。

5 个调用点（grep 确认）：

| 调用点 | 用途 |
|---|---|
| `lib/features/professor/pages/professor_page.dart:273` | 教授主页 |
| `lib/features/competition_recommendation/pages/competition_detail_page.dart:195` | 竞赛官网 |
| `lib/features/favorite/pages/favorite_page.dart:338` | 收藏项外链 |
| `lib/features/home/pages/home_page.dart:297,313` | 首页推荐链接 |
| `lib/features/chat/pages/chat_page.dart:122` | chat 内链接 |

全部走 `linkLauncherProvider.open(url)`，单参数 `Future<LaunchResult> open(String? url)`。

## 总体策略

**透明升级，接口不变**：`LinkLauncher.open(String?)` 签名与 `LaunchResult` 语义保持不变。Android 上改用原生 `CustomTabsIntent`（默认配置，无定制工具栏色 / 菜单，v1 保持中性风格），无支持浏览器时回退到 `Intent.ACTION_VIEW`，仍失败返回 `LaunchResult.failed`。iOS / web 仍走 `url_launcher` 外跳（今日行为），不回归。

技术选型：

- 新增 MethodChannel `top.schonavi.app/links`，与 `top.schonavi.app/preparation_reminders` / `top.schonavi.app/haptics` 同前缀。
- Kotlin handler 独立成 `LinksChannel.kt`（沿用 `NotificationActionCoordinator.kt` / `HapticsChannel.kt` 的「每通道一文件」惯例）。
- **保留 `url_launcher` 依赖** —— 作为 iOS / web 平台的外跳实现。项目维护完整 iOS 工程（`ios/Runner.xcodeproj`），移除 `url_launcher` 会让 iOS 外链打开回归为 `failed`，不可接受。Android 不再走 `url_launcher`（改走自有通道 + `ACTION_VIEW` 回退），但依赖保留给其它平台。
- Android 侧**显式加 `androidx.browser:browser:1.8.0`** 到 [build.gradle.kts](android/app/build.gradle.kts) `dependencies`。此前 `androidx.browser`（提供 `CustomTabsIntent`）由 `url_launcher` 间接带入；保留 `url_launcher` 时它仍传递可用，但为避免依赖传递可见性的不确定性（传递依赖随时可能在 `url_launcher` 升版时被裁剪），显式声明更稳。
- 不引入 `flutter_custom_tabs` 等第三方包，符合 CLAUDE.md「不引入新库需批准」约束。
- Custom Tabs stock 配置（无 prewarm session、无定制 toolbar 色），v1 最小实现；后续可调。

## 改动

### 3.1 Dart 层 —— `lib/core/launcher/url_launcher_link_launcher.dart`

类名 `UrlLauncherLinkLauncher` 与 `const` 构造保留（[infra_providers_test.dart](test/core/di/infra_providers_test.dart) `isA<UrlLauncherLinkLauncher>()` 断言依赖类名）。校验逻辑（null/空白/缺 scheme/非 http(s)）留在 Dart，保持既有 4 个校验测试不变。合法 URL 走自有通道：

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'link_launcher.dart';

class UrlLauncherLinkLauncher implements LinkLauncher {
  const UrlLauncherLinkLauncher();

  static const _channel = MethodChannel('top.schonavi.app/links');

  @override
  Future<LaunchResult> open(String? url) async {
    final trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty) return LaunchResult.noUrl;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return LaunchResult.failed;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final r = await _channel.invokeMethod<String>('openUrl', trimmed);
        return r == 'success' ? LaunchResult.success : LaunchResult.failed;
      } on PlatformException catch (_) {
        return LaunchResult.failed;
      } on MissingPluginException catch (_) {
        return LaunchResult.failed;
      }
    }
    // iOS / web：保留 url_launcher 外跳（今日行为），不回归。
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return ok ? LaunchResult.success : LaunchResult.failed;
    } catch (_) {
      return LaunchResult.failed;
    }
  }
}
```

要点：

- **校验在 Dart**：null/空白 → `noUrl`，非 http(s)/解析失败 → `failed`，与既有 4 个校验测试一致。
- **Android 路径**：走自有 `links` 通道；`"success"` → `LaunchResult.success`，其它 / `PlatformException` / `MissingPluginException` → `LaunchResult.failed`。回退链（Custom Tabs → `ACTION_VIEW` → `failed`）全在 Kotlin。
- **iOS/web 路径**：仍走 `url_launcher` 外跳（`LaunchMode.externalApplication`），保留今日行为，零回归。
- **`url_launcher` 依赖保留**：iOS/web 分支使用；Android 分支不再走它。

### 3.2 Kotlin 层 —— 新文件 `android/app/src/main/kotlin/com/example/scho_navi/LinksChannel.kt`

```kotlin
package top.schonavi.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object LinksChannel {
    private const val CHANNEL_NAME = "top.schonavi.app/links"

    fun register(flutterEngine: FlutterEngine) {
        val context = flutterEngine.context
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                if (call.method != "openUrl") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val url = call.arguments as? String
                if (url.isNullOrBlank()) {
                    result.success("failed")
                    return@setMethodCallHandler
                }
                val uri = Uri.parse(url)
                // 1. 试 Custom Tabs
                try {
                    CustomTabsIntent.Builder().build().launchUrl(context, uri)
                    result.success("success")
                    return@setMethodCallHandler
                } catch (_: ActivityNotFoundException) {
                    // 无支持 Custom Tabs 的浏览器，落入 ACTION_VIEW
                } catch (_: Exception) {
                    // 其它异常，落入 ACTION_VIEW
                }
                // 2. 回退 ACTION_VIEW
                try {
                    val view = Intent(Intent.ACTION_VIEW, uri)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(view)
                    result.success("success")
                } catch (_: ActivityNotFoundException) {
                    result.success("failed")
                } catch (_: Exception) {
                    result.success("failed")
                }
            }
    }
}
```

`MainActivity.configureFlutterEngine` 增一行 `LinksChannel.register(flutterEngine)`。

要点：

- **`androidx.browser`**：提供 `CustomTabsIntent`。虽 `url_launcher` 传递依赖带入，但传递可见性不保证（升级 `url_launcher` 时可能被裁剪），故在 [build.gradle.kts](android/app/build.gradle.kts) `dependencies` 显式 `implementation("androidx.browser:browser:1.8.0")`。
- **stock 配置**：`CustomTabsIntent.Builder().build()` 默认主题色跟随系统，无定制菜单，v1 中性风格，后续可调 toolbar 色 / prewarm。
- **`launchUrl` 失败回退**：`ActivityNotFoundException`（无 Custom Tabs 浏览器）→ `ACTION_VIEW`；仍无 handler → `"failed"`。链路保证不劣于今日（今日 `externalApplication` 也是 `ACTION_VIEW` 等价路径）。
- **`FLAG_ACTIVITY_NEW_TASK`**：从非 Activity context（`flutterEngine.context`）启动需 NEW_TASK。
- **返回 `"success"` 时机**：`startActivity` 成功即返回，不等浏览器关闭（与今日 `launchUrl` 语义一致）。

### 3.3 build.gradle.kts —— 显式加 androidx.browser

[android/app/build.gradle.kts](android/app/build.gradle.kts) `dependencies` 块增一行：

```kotlin
dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    implementation("androidx.browser:browser:1.8.0")
}
```

`url_launcher` 依赖保留在 [pubspec.yaml:40](pubspec.yaml#L40) 不动 —— iOS / web 分支仍在用。

## 数据流、边界与错误处理

| 边界 | 处理 |
|---|---|
| null / 空白 URL | Dart → `LaunchResult.noUrl`（与今日一致） |
| 非 http(s) / 解析失败 | Dart → `LaunchResult.failed`（与今日一致） |
| Android 无 Custom Tabs 浏览器 | Kotlin `ActivityNotFoundException` → `ACTION_VIEW` 回退 |
| Android `ACTION_VIEW` 无 handler | Kotlin → `"failed"` → Dart `LaunchResult.failed` |
| iOS / web | Dart → `url_launcher` 外跳（今日行为，不回归） |
| Android 通道未注册 / `PlatformException` | Dart → `LaunchResult.failed` |
| `LaunchResult.noUrl` / `failed` 中文提示 | 现有 toast 映射不变（见 [link_launcher.dart](lib/core/launcher/link_launcher.dart) 注释） |

风险：

- **`androidx.browser` 依赖可见性**：已通过显式 `implementation("androidx.browser:browser:1.8.0")` 规避传递依赖裁剪风险。
- **Custom Tabs 浏览器缺失率**：现代 Android 设备（Chrome / Edge / Firefox 预装）几乎为 0；回退链覆盖该 case。
- **iOS 回归**：已规避 —— iOS / web 保留 `url_launcher` 外跳，行为与今日完全一致。

## 测试与验证

### 单元测试（最小相关优先）

**现有 [test/core/launcher/url_launcher_link_launcher_test.dart](test/core/launcher/url_launcher_link_launcher_test.dart)**（4 个校验测试）：

- null → `noUrl`、空白 → `noUrl`、缺 scheme → `failed`、非 http(s) → `failed` —— 校验逻辑留 Dart，**4 个测试不变、全绿**。

**新增测试**（同文件追加）：

- mock `top.schonavi.app/links` 通道，设 `defaultTargetPlatform = TargetPlatform.android`：
  - `open('https://example.edu.cn')` → 断言通道收到 `'openUrl'` + URL；通道返回 `"success"` → `LaunchResult.success`。
  - 通道返回 `"failed"` → `LaunchResult.failed`。
  - 通道抛 `PlatformException` → `LaunchResult.failed`。
  - 通道抛 `MissingPluginException` → `LaunchResult.failed`。
- iOS/web 平台路径（设 `defaultTargetPlatform = TargetPlatform.iOS`）：`open(合法 url)` → 走 `url_launcher` 外跳（mock `url_launcher` 平台通道，断言 `launchUrl` 被调用，`LaunchMode.externalApplication`），不调自有 `links` 通道。

**[infra_providers_test.dart](test/core/di/infra_providers_test.dart)**：`isA<UrlLauncherLinkLauncher>()` + `isA<LinkLauncher>()` 断言不变，全绿。

### 手测清单（UI 改动必须手测）

设备：Android 真机 / 模拟器（有 Chrome 或其它 Custom Tabs 浏览器）。

1. 教授详情页点「主页」→ Custom Tabs 应用内打开，底部有返回栏，返回回到 app 教授页。
2. 竞赛详情点官网 → 同上，返回回竞赛详情。
3. 收藏页点外链 → Custom Tabs 打开。
4. 首页推荐链接 → Custom Tabs 打开。
5. chat 内链接 → Custom Tabs 打开。
6. 教授页 `homepage` 为 null/空 → toast「暂无主页信息」（`noUrl` 路径不变）。
7. 主页失效（404 URL 或非法 host）→ toast「主页可能已失效，可通过学校官网确认」（`failed` 路径不变）。
8. Custom Tabs 浏览器不可达（理论上模拟器可禁用 Chrome 验证）→ 回退 `ACTION_VIEW` 系统浏览器打开。

### 静态检查

```bash
flutter pub get
flutter analyze
dart format --set-exit-if-changed lib test
flutter test test/core/launcher/url_launcher_link_launcher_test.dart
flutter test test/core/di/infra_providers_test.dart
```

`flutter pub get` 会拉取新增的 `androidx.browser:browser:1.8.0`（Android Gradle 解析）。

### 不做的事

- 不加 per-link `inApp` 参数 / `openExternal` 二方法 —— 5 调用点均无此需求，YAGNI。
- 不做 Custom Tabs prewarm / session 绑定 / 定制 toolbar 色 —— v1 stock。
- 不做 iOS `SFSafariViewController` 原生通道 —— iOS 保留 `url_launcher` 外跳已足够，不扩 iOS 原生层。
- 不改 5 个调用点与 `LinkLauncher` 抽象。

### 完成判定

launcher / providers 测试全绿、`flutter pub get` 成功（含 `androidx.browser`）、`flutter analyze` 无新增 error/warning、手测清单 1–8 全过 → 视为完成。若本地无法起设备 / 模拟器，明确说明，至少交付单测 + Kotlin 编译通过。
