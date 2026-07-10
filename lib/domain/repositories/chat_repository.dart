import '../../core/result/result.dart';
import '../entities/chat_message.dart';
import '../entities/chat_result.dart';
import '../entities/fork_ref.dart';
import '../entities/recommendation_result.dart';

/// 对话仓储。
///
/// 改为 `abstract class` 以给 [seedRecommendationTurn] 提供默认空实现，使
/// 无本地会话历史的实现可以安全忽略上下文注入。
abstract class ChatRepository {
  /// 发送一条追问消息，返回助手回答（非流式兼容接口）。
  /// [sessionId] 维持多轮上下文；[professorId] 可锚定某位导师。
  Future<Result<ChatResult>> sendMessage({
    required String sessionId,
    required String message,
    String? professorId,
  });

  /// 流式回答：逐段 emit 文本增量；完成或被取消时把已生成整段并入会话历史，
  /// 出错则丢弃半句。失败经 Stream 抛 AppException。
  Stream<String> streamReply({
    required String sessionId,
    required String message,
    String? professorId,
  });

  /// 注入一次推荐轮上下文（不写可见消息）。
  ///
  /// 把用户提问记入会话历史（user 角色），并把上一轮推荐摘要以 **system 角色**
  /// 注入对话上下文，供后续追问基于已推荐导师作答。可见的推荐消息（开场
  /// 白 + 卡片）由调用方维护并通过 [persistMessages] 落盘，不由此方法产生。
  ///
  /// 默认空实现适用于由服务端维护会话历史的 HTTP 实现，以及无需本地历史的实现。
  Future<void> seedRecommendationTurn({
    required String sessionId,
    required String userPrompt,
    required RecommendationResult result,
  }) async {}

  /// 持久化会话的可见消息历史（含卡片、kind 等完整状态）。
  ///
  /// HTTP 会话由后端持久化，客户端不落盘业务对话历史
  /// 即复制此方法写入的消息。HTTP 模式默认空实现（后端会话自有历史）。
  Future<void> persistMessages(
    String sessionId,
    List<ChatMessage> messages,
  ) async {}

  /// 从源会话 fork 出一个新会话：复制源的全部历史到新 forkId，
  /// 绑定 professorId。同主session+同professorId 复用已有 fork（不新建）。
  /// 返回 forkId 供后续追问/恢复。
  /// 生产对接：POST /chat/fork {source_session_id, professor_id}
  Future<Result<String>> forkSession({
    required String sourceSessionId,
    required String professorId,
  });

  /// 拉取某个会话（主或 fork）的全部消息历史，供页面恢复。
  /// 生产对接：GET /chat/{id}/history
  Future<Result<List<ChatMessage>>> loadHistory({required String sessionId});

  /// 列出某主 session 下的所有 fork（按 createdAt 倒序），供历史页展开。
  /// 生产对接：GET /chat/sessions/{id}/forks
  Future<Result<List<ForkRef>>> listForks({required String mainSessionId});

  /// 删除某个 fork（子项左滑删除）。主 session 不受影响。
  /// 生产对接：DELETE /chat/forks/{forkId}
  Future<Result<void>> deleteFork({required String forkId});
}
