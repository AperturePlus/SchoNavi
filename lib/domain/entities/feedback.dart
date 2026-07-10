/// 用户反馈类型。
enum FeedbackType { recommendation, missingProfessor, bug, other }

/// 反馈附带的可定位上下文。从场景内联入口或路由 query 还原。
class FeedbackContext {
  const FeedbackContext({
    this.route,
    this.sessionId,
    this.messageId,
    this.professorId,
    this.competitionId,
    this.prompt,
    this.appVersion = '',
    this.dataSourceMode = defaultDataSourceMode,
  });

  /// 当前唯一数据源模式：所有推荐 / 匹配 / 备赛请求均经 HTTP 后端处理。
  static const String defaultDataSourceMode = 'http';

  final String? route;
  final String? sessionId;
  final String? messageId;
  final String? professorId;
  final String? competitionId;
  final String? prompt;
  final String appVersion;
  final String dataSourceMode;

  /// 从路由 query 参数还原上下文。
  factory FeedbackContext.fromQuery(Map<String, String> q) {
    String? take(String key) =>
        q.containsKey(key) && q[key]!.isNotEmpty ? q[key] : null;
    return FeedbackContext(
      route: take('route'),
      sessionId: take('sid'),
      messageId: take('mid'),
      professorId: take('pid'),
      competitionId: take('cid'),
      prompt: take('prompt'),
      appVersion: q['v'] ?? '',
      dataSourceMode: q['mode'] ?? defaultDataSourceMode,
    );
  }

  /// 是否完全没有可定位信息(用于决定是否折叠摘要)。
  bool get isEmpty =>
      route == null &&
      sessionId == null &&
      messageId == null &&
      professorId == null &&
      competitionId == null &&
      prompt == null;

  FeedbackContext copyWith({
    String? route,
    String? sessionId,
    String? messageId,
    String? professorId,
    String? competitionId,
    String? prompt,
    String? appVersion,
    String? dataSourceMode,
  }) => FeedbackContext(
    route: route ?? this.route,
    sessionId: sessionId ?? this.sessionId,
    messageId: messageId ?? this.messageId,
    professorId: professorId ?? this.professorId,
    competitionId: competitionId ?? this.competitionId,
    prompt: prompt ?? this.prompt,
    appVersion: appVersion ?? this.appVersion,
    dataSourceMode: dataSourceMode ?? this.dataSourceMode,
  );
}

/// 一条用户反馈。
class Feedback {
  const Feedback({
    required this.id,
    required this.type,
    required this.content,
    required this.contact,
    required this.context,
    required this.createdAt,
  });

  final String id;
  final FeedbackType type;
  final String content;
  final String? contact;
  final FeedbackContext context;
  final DateTime createdAt;

  Feedback copyWith({
    String? id,
    FeedbackType? type,
    String? content,
    String? contact,
    FeedbackContext? context,
    DateTime? createdAt,
  }) => Feedback(
    id: id ?? this.id,
    type: type ?? this.type,
    content: content ?? this.content,
    contact: contact ?? this.contact,
    context: context ?? this.context,
    createdAt: createdAt ?? this.createdAt,
  );
}
