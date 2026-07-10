import '../../domain/entities/feedback.dart';

class FeedbackContextDto {
  const FeedbackContextDto({
    this.route,
    this.sessionId,
    this.messageId,
    this.professorId,
    this.competitionId,
    this.prompt,
    required this.appVersion,
    required this.dataSourceMode,
  });

  final String? route;
  final String? sessionId;
  final String? messageId;
  final String? professorId;
  final String? competitionId;
  final String? prompt;
  final String appVersion;
  final String dataSourceMode;

  factory FeedbackContextDto.fromEntity(FeedbackContext c) =>
      FeedbackContextDto(
        route: c.route,
        sessionId: c.sessionId,
        messageId: c.messageId,
        professorId: c.professorId,
        competitionId: c.competitionId,
        prompt: c.prompt,
        appVersion: c.appVersion,
        dataSourceMode: c.dataSourceMode,
      );

  factory FeedbackContextDto.fromJson(Map<String, dynamic> json) =>
      FeedbackContextDto(
        route: json['route'] as String?,
        sessionId: json['session_id'] as String?,
        messageId: json['message_id'] as String?,
        professorId: json['professor_id'] as String?,
        competitionId: json['competition_id'] as String?,
        prompt: json['prompt'] as String?,
        appVersion: json['app_version'] as String? ?? '',
        dataSourceMode:
            json['data_source_mode'] as String? ??
            FeedbackContext.defaultDataSourceMode,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (route != null) 'route': route,
    if (sessionId != null) 'session_id': sessionId,
    if (messageId != null) 'message_id': messageId,
    if (professorId != null) 'professor_id': professorId,
    if (competitionId != null) 'competition_id': competitionId,
    if (prompt != null) 'prompt': prompt,
    'app_version': appVersion,
    'data_source_mode': dataSourceMode,
  };
}

class FeedbackDto {
  const FeedbackDto({
    required this.id,
    required this.type,
    required this.content,
    required this.contact,
    required this.context,
    required this.createdAt,
  });

  final String id;
  final String type; // recommendation|missing_professor|bug|other
  final String content;
  final String? contact;
  final FeedbackContextDto context;
  final String createdAt; // ISO8601

  static const _typeMap = {
    FeedbackType.recommendation: 'recommendation',
    FeedbackType.missingProfessor: 'missing_professor',
    FeedbackType.bug: 'bug',
    FeedbackType.other: 'other',
  };

  factory FeedbackDto.fromEntity(Feedback f) => FeedbackDto(
    id: f.id,
    type: _typeMap[f.type]!,
    content: f.content,
    contact: f.contact,
    context: FeedbackContextDto.fromEntity(f.context),
    createdAt: f.createdAt.toIso8601String(),
  );

  factory FeedbackDto.fromJson(Map<String, dynamic> json) => FeedbackDto(
    id: json['id'] as String? ?? '',
    type: json['type'] as String? ?? 'other',
    content: json['content'] as String? ?? '',
    contact: json['contact'] as String?,
    context: FeedbackContextDto.fromJson(
      (json['context'] as Map<String, dynamic>?) ?? const {},
    ),
    createdAt:
        json['created_at'] as String? ?? DateTime.now().toIso8601String(),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'type': type,
    'content': content,
    if (contact != null) 'contact': contact,
    'context': context.toJson(),
    'created_at': createdAt,
  };
}
