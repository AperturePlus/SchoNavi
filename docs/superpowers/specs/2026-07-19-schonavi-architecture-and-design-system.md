# SchoNavi 架构与设计系统规格

- 日期：2026-07-19
- 配套产品规格：[2026-07-19-schonavi-product-spec.md](2026-07-19-schonavi-product-spec.md)
- 状态：绿地项目架构基线已锁定，待按阶段拆分 implementation plan
- 适用范围：Android、Web、主 API、跨端契约、数据所有权、设计系统、测试与工程门槛

## 文档定位

本文描述全新 SchoNavi 项目的完整目标架构和跨端设计规则，可以与配套产品规格一起直接放入空 monorepo，作为开发 AI 和工程团队的初始真相源。

两份规格的职责如下：

- 产品规格定义用户、差异化、功能边界、信息架构、信任机制、指标和阶段门槛。
- 本文定义技术边界、模块职责、协议、数据所有权、视觉语言、交互约束和验证方法。
- `packages/api-contract` 中的 OpenAPI 与 SSE schema 定义可生成的线协议，但不得擅自改变两份规格的产品语义。
- 每个阶段的 implementation plan 负责落到具体文件、依赖版本、任务顺序和测试命令。

发生冲突时不能由实现自行猜测：先修订对应规格或契约，再继续编码。

## AI 执行约定

开发 AI 必须完整阅读两份规格，并遵守以下顺序：

1. 确认当前获准阶段及完成门槛。
2. 先产出该阶段 implementation plan，列出契约变化、风险和验证命令。
3. 只创建当前阶段需要的模块，不预建空 feature、微服务、队列或爬虫目录。
4. 先实现最窄的端到端纵切，再扩展同层能力。
5. 通过最小相关测试、契约检查和人工黄金路径验证后，才报告完成。

不得以“未来可能需要”为理由扩大范围。需要改变固定技术栈、数据所有权或公开契约时，必须先修订本文。

## 固定技术基线

| 层 | 选型 | 角色 |
|---|---|---|
| Android | Kotlin、Jetpack Compose、Material 3 | 主产品客户端 |
| Web | Next.js App Router、React、TypeScript | 桌面与浏览器客户端 |
| 主 API | TypeScript、Node.js 当前 LTS、NestJS、Fastify Adapter | 独立的模块化单体业务服务 |
| 主数据库 | PostgreSQL | 云端权威业务与审计数据 |
| 跨端契约 | OpenAPI、JSON REST、SSE schema | Android、Web、API 之间的公开边界 |
| TypeScript workspace | pnpm workspaces | 管理 Web、API 和 TypeScript packages |
| Android 构建 | Gradle Wrapper + version catalog | 独立、可复现的 Android 构建 |

固定约束：

- 不开发 iOS 或 Flutter 客户端。
- 主 API 不使用 Python 或 Go。
- 不用 Next.js Route Handlers 承载核心业务；它们只可用于 Web 专属薄 BFF、认证回调和页面组合。
- 不使用 tRPC 或只能被 TypeScript 客户端消费的私有协议替代 OpenAPI。
- 首期不引入微服务、Redis、消息队列、Turborepo 或 Nx；只有经测量的需求才能触发新增基础设施。
- 爬虫、批量采集和外部数据清洗不在当前项目范围。未来如需要，作为独立服务另立规格，通过版本化摄入契约提交候选事实，不直接写产品可见数据。

依赖的具体版本、ORM、数据库 schema migration 工具和生成器在 Phase 0 implementation plan 中选择并锁定；选择必须支持当前 LTS、自动化测试和离线可复现构建。

## Monorepo 边界

```text
apps/
  android/                  # Kotlin + Compose 应用及 Android 生成客户端
  web/                      # Next.js + TypeScript
services/
  api/                      # NestJS + Fastify 模块化单体
packages/
  api-contract/             # OpenAPI、SSE schema、契约 fixture
  design-tokens/            # 平台中立的语义 token
  web-api-client/           # OpenAPI 生成的 TypeScript 客户端
  test-fixtures/            # 脱敏、确定性的跨端样例
  typescript-config/        # TS 基础配置；有第二个消费者时再创建
infra/                      # 本地数据库、部署和可观测性配置
docs/
  specs/                    # 本文与产品规格
  plans/                    # 按阶段创建的 implementation plan
```

目录是职责边界，不是要求 Phase 0 一次创建全部空目录。Android 生成代码留在 Gradle 管理的构建目录或专用模块，不进入 TypeScript package。跨端共享的是 schema、语义 token、文案键、fixture 和验收行为，不共享运行时 UI 组件。

根级 CI 可以编排 pnpm 与 Gradle，但两套构建必须能独立运行。生成物由源 schema 重新产生，不手工编辑，也不要求另一端先构建才能编译。

## 总体架构原则

### 依赖方向

```text
UI / Transport → Application → Domain ← Adapters / Persistence
```

- UI 和 Controller 只负责输入输出、状态呈现和协议转换。
- Application 层组织 use case、授权、事务与跨领域流程。
- Domain 层保存实体、值对象、状态机和纯业务规则，不依赖 Compose、Next.js、NestJS 或 ORM 类型。
- Adapter 实现网络、数据库、本地存储、系统能力和第三方服务。
- 跨模块协作通过公开 application port；禁止跨模块直接访问表或内部 repository。

### 模块化单体

主 API 首期只有一个可部署服务。目标业务模块包括：

- `identity`：游客、账号、会话、资产认领。
- `profiles`：主动档案、待确认推断、授权。
- `facts`：教授/竞赛事实、来源、核验与冲突。
- `decisions`：推荐、查询理解和匹配解释。
- `conversations`：会话、轮次、attempt、fork 与 SSE。
- `workspaces`：候选、计划、任务、对比、邮件和归档摘要。
- `cases`：案例草稿、发布、成熟度、报告与撤回。
- `feedback`：产品反馈和消息内反馈。
- `moderation`：审核、举报、隐私风险与审计。

模块只在对应产品阶段开始时创建。`workspaces` 可以提供聚合摘要，但不能用一个万能实体取代生命周期不同的计划、候选、对比和邮件。

## 平台架构

### Android

- UI：Jetpack Compose + Material 3，Composable 尽量无状态，由上层传入不可变 UI state 和事件回调。
- 状态：ViewModel + Coroutines/StateFlow；一次性导航和通知事件不得建模为可重放的长期页面状态。
- 导航：Navigation Compose；每个一级入口保留自己的返回栈和必要页面状态。
- 依赖注入：选择一个 Kotlin/Android 成熟方案并在 Phase 0 锁定；业务代码依赖接口而非容器 API。
- 网络：OkHttp 与 OpenAPI 生成的 Kotlin 客户端；SSE 使用同一认证、request ID 和错误映射基础设施。
- 本地：Room 保存结构化游客资产与可丢弃缓存，DataStore 保存偏好；凭证由 Android Keystore 支撑。
- 后台：WorkManager 承担可靠提醒同步和可延期任务；普通 UI 协程不能冒充后台任务。
- 系统能力：提醒、系统分享、深链、触觉和外链通过接口隔离，便于测试替换。

建议的目标模块边界是 `app`、`core:model`、`core:network`、`core:database`、`core:designsystem` 和按产品阶段出现的 `feature:*`。不要为尚未获准的功能提前创建空 Gradle module。

### Web

- 使用 Next.js App Router；Server Components 是默认选择，只有浏览器能力、交互状态和流式消费需要 Client Components。
- 页面通过生成的 TypeScript 客户端访问主 API，不复制后端业务规则或 DTO。
- Route Handler/Server Action 可以组合 Web 表单和认证上下文，但最终业务命令仍进入主 API。
- 路由级 `loading`、`error` 和 not-found 状态必须定义；异步区域预留尺寸，避免内容跳动。
- 响应式布局不追求 Android 页面逐像素复制，而保持相同信息层级、事实状态和业务动作。
- 浏览器存储只保存游客草稿、偏好和可丢弃缓存；安全会话优先使用 HttpOnly、Secure、SameSite cookie。

### 主 API

- NestJS Controller 处理 transport，application service 处理 use case，domain 保存规则，adapter 处理 PostgreSQL 与外部服务。
- Fastify Adapter 是唯一 HTTP adapter；禁止模块自行启动第二个 HTTP server。
- ORM 实体不是公开 API DTO，也不是跨模块领域模型。
- 事务边界由 application use case 明确控制；不可把长时间 LLM 流式调用包在数据库事务中。
- LLM 输出只能总结和推理候选事实，不能创建不存在的教授、竞赛、来源或证据。
- 队列、独立 worker 和缓存只能在存在明确的重试、调度、吞吐或延迟指标后引入。

## 数据所有权与同步

### 云端权威数据

以下数据由主 API 和 PostgreSQL 权威持有：

- 账号、认证会话与资产认领记录。
- 用户确认后的档案和授权状态。
- 教授、竞赛事实及其来源、适用期、核验状态和变更记录。
- 推荐、对话、历史、收藏和反馈。
- 登录用户的候选、计划、任务、对比、邮件及作战室摘要。
- 案例、发布授权、审核、报告、撤回和删除记录。

客户端只能经公开 API 访问这些数据。缓存可用于性能和短暂离线展示，但必须携带版本或新鲜度，不能在失败时伪装成最新事实。

### 设备本地数据

- 游客计划和草稿。
- 未发送输入与临时编辑状态。
- UI、主题、提醒偏好和通知调度状态。
- 可安全丢弃并重新获取的缓存。

游客登录后必须看到显式认领/合并流程。系统比较本地与云端 ID、revision 和更新时间，展示冲突选项，不静默覆盖。需要 Android 与 Web 同步的资产在认领后转为云端权威数据。

### 乐观并发与幂等

- 可变资产包含 `revision`；更新携带 `expected_revision` 或等价条件请求。
- 冲突返回稳定业务错误码和最新资源摘要，客户端提供刷新、比较或重试动作。
- 创建、提交轮次、应用计划改动等可重试命令携带 `Idempotency-Key`。
- 每次请求携带或接收 `X-Request-ID`；request ID 贯穿日志、错误反馈和用户支持。

## API 与流式契约

### OpenAPI

`packages/api-contract` 是 REST 线协议真相源：

- 使用 HTTP 状态码和具体成功 schema，不套通用业务成功信封。
- 错误使用统一 problem schema，至少包含 `type`、`title`、`status`、`code`、`detail`、`request_id` 和可选 `field_errors`。
- 日期和时间戳是不同类型：日历日期使用 `YYYY-MM-DD`，时间点使用带时区的 RFC 3339 字符串。
- 枚举在线协议中使用稳定字符串，不使用数据库序号。
- 分页使用 cursor，不允许大型列表依赖不稳定的 offset。
- 破坏性契约变化必须被 CI 发现；客户端生成物不得手改。

### SSE 对话协议

对话提交使用支持请求体和自定义请求头的 HTTP streaming 请求，响应媒体类型为 `text/event-stream`。Web 使用 Fetch streaming，Android 使用 OkHttp 流式读取。

事件类型固定为：

| 事件 | 作用 | 关键字段 |
|---|---|---|
| `ack` | 服务端接受本次 attempt | session_id、turn_id、attempt_id、revision、request_id |
| `route` | 声明本轮路由 | route、reason、可选锚点 |
| `delta` | 增量助手文本 | attempt_id、sequence、text |
| `completed` | 唯一成功终态 | final_message、session_snapshot、quick_actions、revision |
| `error` | 唯一失败终态 | problem、retryable、last_sequence |

约束：

- 每个 attempt 最多一个终态；断流不能被当成成功。
- `sequence` 单调递增，客户端忽略重复 delta 并能检测缺口。
- 事件 parser、状态机和错误映射在 Android/Web 各有独立单测，并共享相同 fixture。
- 取消只取消当前 attempt，不删除已经确认的轮次和资产。
- 重试复用幂等键或创建明确的新 attempt，不能产生两条不可区分的助手结果。

## 事实可信度模型

任何进入推荐、计划或案例的关键事实至少包含：

```text
source_url
source_name
source_type
verified_at
applicable_period
freshness_status
conflict_note
```

`freshness_status` 至少支持 `verified`、`stale`、`conflicting` 和 `unknown`。状态变化必须能追踪受影响的推荐和作战资产。

界面必须同时呈现事实、来源、最后核验时间、适用范围和不确定项。AI 推理不能覆盖事实状态，也不能把相似案例当成官方来源。

## 核心领域模型

字段在 OpenAPI 和领域 implementation plan 中细化，以下语义必须保留：

- `ConversationSession`：会话类型、owner、revision、fork 来源和生命周期。
- `ConversationTurn`：ordinal、用户输入、路由、活动 attempt 和状态。
- `ConversationAttempt`：一次生成尝试、幂等键、序列、终态和诊断。
- `RecommendationResult`：查询理解、推荐列表、限制、来源和追问建议。
- `FactReference`：来源、适用范围、核验状态和冲突说明。
- `PreparationPlan`：竞赛快照、目标日期、阶段、任务、revision、状态和个性化摘要。
- `PlanChangeSet`：针对明确 base revision 的结构化计划修改，需验证后才能应用。
- `WorkspaceItemSummary`：跨资产列表摘要，不承担所有资产的持久化模型。
- `ProfileSuggestion`：从对话产生、尚未确认的档案建议，支持接受、修改、拒绝和撤销。
- `Case`：目标、脱敏背景、计划、实际偏差、结果、复盘、成熟度和核验等级。

DTO/生成 transport model 不直接成为 UI state。Android 和 Web 分别映射为适合平台的不可变模型；主 API 的 domain model 不承担 JSON 或 ORM 序列化职责。

## 设计系统

### 设计原则

SchoNavi 的视觉目标是“可信、冷静、可行动”，而不是通用 AI 的紫粉渐变，也不是社区产品的高密度内容流。主要识别点来自：

1. 事实来源和新鲜度始终可见。
2. 推荐理由、限制条件和下一步具有稳定层级。
3. 作战资产以状态、期限和进度为视觉主轴。
4. AI 内容与已核验事实、真人案例有明确视觉边界。

设计必须优先保证信息可信度、可读性和无障碍。玻璃模糊、渐变和动效只能增强层级，不能成为品牌的唯一识别方式。

### 语义颜色

`packages/design-tokens` 使用语义名，不允许业务组件直接依赖 `blue500`、`indigo600` 等原始色名。

| 语义 | Light 基准 | Dark 基准 | 用途 |
|---|---|---|---|
| `background.canvas` | `#F8FAFC` | `#0B1120` | 页面底色 |
| `surface.panel` | `#FFFFFF` | `#111827` | 主面板和卡片 |
| `content.primary` | `#0F172A` | `#F8FAFC` | 正文和标题 |
| `content.secondary` | `#475569` | `#CBD5E1` | 次级说明 |
| `action.primary` | `#0369A1` | `#38BDF8` | 主操作、焦点、链接 |
| `evidence.verified` | `#0F766E` | `#5EEAD4` | 已核验来源 |
| `evidence.stale` | `#B45309` | `#FBBF24` | 过期或需复核 |
| `status.danger` | `#BE123C` | `#FDA4AF` | 错误和破坏性操作 |

实际前景/背景组合必须通过对比度测试。颜色不能独自表达状态；同时使用文字、图标或形状。

### 字体与排版

- 中文正文优先使用平台系统中文字体或可稳定自托管的思源黑体/Noto Sans SC，不依赖运行时下载字体。
- Android 通过 Material 3 typography 映射，Web 通过根 layout 统一字体和 CSS token。
- Web 正文基准不小于 16px；正文行高 1.5–1.7，长文行宽控制在约 60–75 个字符。
- 标题依靠字号、字重和留白建立层级，不使用大面积艺术字体影响中文可读性。
- 数字、日期和状态在卡片间保持对齐规则，截止日期不得被弱化为次要脚注。

### 面层、形状与动效

- 页面使用 canvas、panel、surface、overlay 四级面层。
- 卡片圆角基准 16，输入 14，底部表/对话框顶角 24；平台组件可按 Material 3 或 Web 语义适配。
- 玻璃模糊只用于固定导航、输入栏和临时浮层；长列表项使用不透明面层，并提供低性能/高对比模式降级。
- 微交互动效以 150–300ms 为基准，优先 transform/opacity；不能通过缩放造成布局位移。
- 所有骨架屏预留最终内容空间；思考动画不能暗示不存在的具体推理步骤。

### 核心组件合同

- **EvidenceBlock**：来源名称、类型、适用期、核验时间、freshness 和冲突说明。
- **DecisionCard**：对象摘要、为何适合、限制、关键事实、下一步和保存动作。
- **WorkspaceCard**：资产状态、下一任务、截止日期、进度、需要处理原因和 revision/stale 状态。
- **CaseCard**：来源类型、成熟度、核验等级、适用年份和“为什么与我相似”。
- **ConversationComposer**：输入、显式上下文附件、发送/取消、流式状态和错误恢复。
- **StreamingMessage**：ack、route、delta、completed/error 状态可判定，不能无限显示“思考中”。
- **AsyncBoundary**：loading、empty、error、stale、retry 五态完整。

Android 和 Web 可以采用不同布局，但组件合同中的信息与动作不能丢失。

### 导航与响应式

- Android 最终目标为决策、作战室、案例、我四个一级入口；案例未达到产品门槛前不占一级导航。
- Android 返回键优先退出当前详情层级，在一级根页面按产品约定退出应用。
- Web 在窄屏使用底部/紧凑导航，在宽屏使用侧栏或双栏工作区；核心任务在 375、768、1024 和 1440px 宽度验证。
- 每个一级入口保留自己的导航和必要输入状态；深链进入详情后能返回正确入口。
- 核心功能不能只通过滑动、hover、右键或隐藏手势访问。

### 无障碍

- Android 触控目标至少 48×48dp；Web 触控/指针目标至少 44×44 CSS px。
- 普通文字对比度至少 4.5:1；焦点环在所有 Web 交互元素上可见。
- Android 图标按钮提供正确语义，Web 图标按钮具有可访问名称；tooltip 不能替代名称。
- Web 的 tab 顺序与视觉顺序一致，表单有真实 label，错误紧邻相关字段并汇总到可聚焦区域。
- 横向卡片同时提供按钮、键盘和屏幕阅读器操作，宣布“第 N 张，共 M 张”。
- 尊重 Android 系统动画设置和 Web `prefers-reduced-motion`。
- 有意义图片提供替代文本；装饰图从无障碍树隐藏。
- 图标使用一致的矢量体系，不使用 emoji 充当功能图标。

## 状态与错误模型

客户端可处理错误至少分为：网络不可达、超时、认证失效、无权限、验证失败、资源不存在、revision 冲突、限流、上游事实不可用、服务异常和未知错误。

每个错误映射为：

- 面向用户的安全中文文案。
- 稳定机器错误码。
- 是否可重试及建议动作。
- request ID 和不含敏感数据的诊断信息。

异步命令处理中禁用重复提交；失败后保留用户输入。删除、覆盖、发布、撤回和账号删除必须确认，并在可行时提供撤销或明确恢复路径。

## 测试与质量门槛

### 契约

- OpenAPI lint、兼容性检查和 Kotlin/TypeScript 客户端生成。
- Android/Web 对相同 SSE fixture 的解析和状态机测试。
- problem、日期、枚举、分页、revision 和幂等 fixture 往返测试。
- API 实现与公开契约的自动漂移检查。

### Android 测试

- Domain/application 纯逻辑单测。
- Repository 使用 fake、临时 Room 和 MockWebServer 测试。
- ViewModel 状态机测试覆盖 loading、empty、error、stale、retry、取消和冲突。
- Compose UI 测试覆盖黄金路径、返回键、深链、动态字体和无障碍语义。
- 关键阶段在真机或模拟器验证，不以单测代替触控和系统行为检查。

### Web 测试

- 领域映射和流式 reducer 单测。
- 使用固定 fixture/MSW 的组件测试，不接生产数据。
- 浏览器测试覆盖键盘导航、焦点恢复、响应式布局和核心黄金路径。
- 验证 Server/Client Component 边界、错误页和 loading UI，避免不必要的客户端 bundle。

### API 测试

- Domain/application 单测覆盖授权、状态转换、事实新鲜度和案例成熟度规则。
- PostgreSQL adapter 使用隔离集成测试验证事务、约束和并发。
- Controller/contract 测试验证状态码、problem、幂等键、request ID 和 SSE 终态。
- LLM 测试使用确定性 stub，验证不制造候选事实；真实模型评测单独运行，不作为普通单测前置条件。

### 端到端黄金路径

Phase 1 至少覆盖：

```text
提交竞赛需求
→ 查看查询理解和来源
→ 保存为计划
→ 确认下一步
→ 再次打开同一资产
→ 更新一次真实进度
```

该路径必须同时验证 request ID、SSE 完成、revision 更新、错误恢复和事件埋点。

## 安全、隐私与可观测性

- 密钥、token、真实个人数据和生产配置不得进入仓库。
- 日志默认脱敏，不记录完整对话、档案、邮件正文或认证凭证。
- 权限检查在服务端执行，客户端隐藏按钮不能代替授权。
- 案例发布保存用户确认版本、授权范围和审核轨迹；撤回后不再向新请求返回。
- 账号删除和数据导出是明确的异步状态流程，提供 request ID、进度和结果。
- 关键链路记录结构化日志、延迟、错误码和业务事件；指标名称及隐私边界在阶段 plan 中定义。

## Phase 0 工程完成判定

Phase 0 只建立可持续开发的最小基础：

1. pnpm workspace、Android Gradle 和主 API 能独立构建。
2. PostgreSQL 本地开发环境和 API 健康检查可运行。
3. 最小 OpenAPI、统一 problem、request ID 和客户端生成链路可验证。
4. Android 与 Web 各有一个使用语义 token 的静态壳页面，但不预建未验证业务 tab。
5. CI 独立执行 TypeScript lint/typecheck/test、Android 编译/静态检查和契约检查。
6. 根级 README 只说明启动与验证；根级 AGENTS.md 写明阶段边界、生成代码、依赖和密钥规则。
7. 没有爬虫、案例、消息队列、微服务或空 feature 占位实现。

Phase 0 完成后，才能按产品规格进入 Android + TypeScript API 的竞赛薄闭环。

## 明确不做

- 不开发 iOS、Flutter 客户端或桌面套壳。
- 不把 Web、Android 和 API 强行做成同一目录结构或共享运行时模型。
- 不把核心业务放入 Next.js，也不让客户端直连 PostgreSQL。
- 不在事实可信度、身份、授权和撤回机制完成前开放公开案例。
- 不预建小红书式信息流、关系、私信、泛评论或创作者排行。
- 不使用 AI 示范内容冒充真人案例或参与质量飞轮。
- 不在当前项目实现爬虫、采集调度、反爬或外部数据清洗。
- 不因 monorepo 自动引入微服务、队列、Redis、Turborepo 或 Nx。
- 不用本地 fallback 伪装云端权威事实或静默吞掉网络错误。

## 本规格完成判定

本文达到可执行状态需满足：

1. 与产品规格在技术栈、数据所有权、导航阶段和案例门槛上无冲突。
2. 两份文档在空 monorepo 中即可独立理解和执行。
3. Phase 0 implementation plan 能从本文明确得到目录边界、生成链路、验证命令类型和禁止事项。
4. 未决的具体库版本、ORM 和部署方案被明确留给 Phase 0，而不是由开发 AI 静默决定并扩散。
