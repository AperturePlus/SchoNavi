# SchoNavi

SchoNavi 是一个 Flutter 应用。应用入口位于 `lib/main.dart`，应用壳位于 `lib/app.dart`。

## 模块

- `lib/core`：应用配置、路由、主题、依赖注入、AI 客户端、本地存储和外链能力。
- `lib/domain`：业务实体与 repository 接口。
- `lib/data`：候选事实数据、本地持久化、LLM repository 实现和 DTO。
- `lib/features`：首页、推荐、教授详情、聊天、邮件、对比、收藏和历史页面。
- `lib/shared`：跨页面复用组件。
- `test`：对应模块的测试。

## 架构

项目采用 Flutter UI + Riverpod 状态管理/依赖注入 + GoRouter 路由。业务层通过 `domain` 中的 repository 接口隔离，数据层在 `data` 中提供候选事实、本地持久化和 LLM 等实现，由 `core` 中的配置与 provider 统一接线。

## Android 构建

先复制构建配置示例到本地配置文件：

```powershell
Copy-Item config/android_apk_build.example.json config/android_apk_build.local.json
```

然后编辑 `config/android_apk_build.local.json`，填写后端地址并选择 APK 类型：

```json
{
  "backend": {
    "scheme": "http",
    "host": "YOUR_HOST",
    "port": 8000
  },
  "apk": {
    "target": "armv8"
  }
}
```

`target` 只支持两个值：

- `universal`：生成通用 APK，产物为 `build/app/outputs/flutter-apk/app-release.apk`。
- `armv8`：生成 arm64-v8a APK，产物为 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`。

运行构建：

```powershell
dart run scripts/build_android_apk.dart
```

检查将执行的 Flutter 命令但不真正构建：

```powershell
dart run scripts/build_android_apk.dart --dry-run
```

使用其他配置文件：

```powershell
dart run scripts/build_android_apk.dart --config config/android_apk_build.example.json --dry-run
```

脚本会把配置拼成 `API_BASE_URL=<scheme>://<host>:<port>` 并传给 Flutter。`API_BASE_URL` 是后端 origin，不要包含 `/api/v1`；客户端会自行拼接 `/api/v1/...` 路径。

Android 模拟器访问本机后端时，`host` 使用 `10.0.2.2`。当前 Android 明文 HTTP 只放行 `10.0.2.2` 和 `localhost`；真机访问普通 `http://局域网IP:端口` 需要 HTTPS，或另行调整 Android 网络安全配置。

## VS Code 启动配置

可在 `.vscode/launch.json` 中使用以下配置。LLM 模式通过 VS Code 输入框传入 API Key，不在文件中写入真实密钥；未配置 `LLM_API_KEY` 时，大模型功能会显式报错而不会回退到本地推荐。

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "SchoNavi Flutter (LLM, no key)",
      "request": "launch",
      "type": "dart",
      "program": "lib/main.dart"
    },
    {
      "name": "SchoNavi Flutter (LLM)",
      "request": "launch",
      "type": "dart",
      "program": "lib/main.dart",
      "toolArgs": [
        "--dart-define=LLM_API_KEY=${input:llmApiKey}",
        "--dart-define=LLM_BASE_URL=https://api.deepseek.com",
        "--dart-define=LLM_MODEL=deepseek-chat"
      ]
    }
  ],
  "inputs": [
    {
      "id": "llmApiKey",
      "type": "promptString",
      "description": "LLM API Key",
      "password": true
    }
  ]
}
```

真实后端模式通过 `--dart-define=API_BASE_URL=https://api.example.com` 开启。
`API_BASE_URL` 填后端 origin，不要包含 `/api/v1`；客户端会自行拼接
`/api/v1/...` 路径。
