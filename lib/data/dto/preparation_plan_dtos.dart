import '../../core/calendar_date.dart';
import '../../domain/entities/preparation_plan.dart';
import '../../domain/entities/user_profile.dart';
import 'profile_dtos.dart';

/// AI 个性化请求：携带竞赛快照、赛事时间模型、目标日期、赛事窗口、答辩日、
/// 日历基准、每周投入、经验等级、阶段 key 列表与可选学生档案。供
/// [PreparationPersonalizer] HTTP 实现消费。
class PreparationPersonalizationRequest {
  const PreparationPersonalizationRequest({
    required this.competition,
    required this.timelineType,
    required this.targetDate,
    this.eventEndDate,
    this.defenseDate,
    required this.calendarToday,
    required this.weeklyCommitment,
    required this.experienceLevel,
    required this.phaseKeys,
    this.profile,
  });

  final CompetitionSnapshot competition;

  /// 赛事时间模型：窗口型（比赛集中在几天）/ 提交型（作品提交到 DDL）。
  final CompetitionTimelineType timelineType;
  final DateTime targetDate;

  /// 赛事窗口结束日（窗口型有意义）；提交型可空。
  final DateTime? eventEndDate;

  /// 答辩日（仅提交型且需答辩时存在）；窗口型与无答辩提交型为 null。
  final DateTime? defenseDate;

  /// 日历基准（spec §2.1）：排期与预算的权威今天。
  final DateTime calendarToday;
  final WeeklyCommitment weeklyCommitment;
  final ExperienceLevel experienceLevel;

  /// 合法阶段 key 白名单：AI 返回的 phaseKey 必须在此集合内，否则丢弃。
  /// 含 defense_prep 当且仅当 defenseDate != null。
  final List<String> phaseKeys;
  final UserProfile? profile;

  /// 序列化为 HTTP 请求体（spec §7.2 结构）。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'competition': competition.toJson(),
    'timeline_type': timelineType.name,
    'target_date': CalendarDate.toIsoDay(targetDate),
    if (eventEndDate != null)
      'event_end_date': CalendarDate.toIsoDay(eventEndDate!),
    if (defenseDate != null)
      'defense_date': CalendarDate.toIsoDay(defenseDate!),
    'calendar_today': CalendarDate.toIsoDay(calendarToday),
    'weekly_commitment': weeklyCommitment.name,
    'experience_level': experienceLevel.name,
    'phase_keys': phaseKeys,
    if (profile != null && !profile!.isEmpty)
      'user_profile': UserProfileDto.fromEntity(profile!).toJson(),
  };
}

/// 单条可选任务建议。
class PreparationOptionalTaskSuggestion {
  const PreparationOptionalTaskSuggestion({
    this.templateKey,
    required this.title,
    required this.estimatedHours,
  });

  final String? templateKey;
  final String title;
  final double estimatedHours;

  @override
  String toString() =>
      'PreparationOptionalTaskSuggestion(templateKey: $templateKey, '
      'title: $title, estimatedHours: $estimatedHours)';
}

/// 单阶段个性化结果。
class PreparationPhasePersonalization {
  const PreparationPhasePersonalization({
    required this.key,
    required this.optionalTasks,
    this.personalizedAdvice,
  });

  final String key;
  final List<PreparationOptionalTaskSuggestion> optionalTasks;
  final String? personalizedAdvice;

  @override
  String toString() =>
      'PreparationPhasePersonalization(key: $key, optionalTasks: $optionalTasks, '
      'personalizedAdvice: $personalizedAdvice)';
}

/// 个性化结果信封：若干阶段个性化 + 全局建议。
class PreparationPersonalizationResult {
  const PreparationPersonalizationResult({
    required this.phases,
    this.globalAdvice,
  });

  final List<PreparationPhasePersonalization> phases;
  final String? globalAdvice;

  @override
  String toString() =>
      'PreparationPersonalizationResult(phases: $phases, '
      'globalAdvice: $globalAdvice)';
}

/// DTO：从后端返回的 JSON `data` 解码为 [PreparationPersonalizationResult]。
///
/// 解码同时承担 spec §7.2 的校验/丢弃职责（与
/// HTTP 客户端共用同一套规则）：
/// - 未知 phaseKey（不在请求 phaseKeys 白名单内）→ 丢弃该阶段。
/// - 阶段内重复 templateKey（非空）→ 仅保留首条，其余丢弃。
/// - 每阶段 optionalTasks > 3 → 截断/丢弃超量项。
/// - 非法字段（title 空 / estimatedHours 非数 / 非对象）→ 跳过。
/// - 整体结构非对象或 phases 非 List → 抛 [FormatException]，由调用方
///   兜底转 `Failure(ServerException)`。
class PreparationPersonalizationResultDto {
  PreparationPersonalizationResultDto({
    required this.phases,
    this.globalAdvice,
  });

  final List<PreparationPhasePersonalization> phases;
  final String? globalAdvice;

  /// 从 JSON `data` 解码。`phaseKeys` 为合法阶段白名单。
  factory PreparationPersonalizationResultDto.fromJson(
    Map<String, dynamic> json, {
    required Set<String> phaseKeys,
  }) {
    final rawPhases = json['phases'];
    if (rawPhases is! List) {
      return PreparationPersonalizationResultDto(phases: const []);
    }

    final phases = <PreparationPhasePersonalization>[];
    for (final item in rawPhases) {
      if (item is! Map) continue;
      final phase = _parsePhase(
        Map<String, dynamic>.from(item),
        phaseKeys: phaseKeys,
      );
      if (phase != null) phases.add(phase);
    }

    return PreparationPersonalizationResultDto(
      phases: phases,
      globalAdvice: _optionalString(
        json['global_advice'] ?? json['globalAdvice'],
      ),
    );
  }

  PreparationPersonalizationResult toEntity() =>
      PreparationPersonalizationResult(
        phases: phases,
        globalAdvice: globalAdvice,
      );

  static PreparationPhasePersonalization? _parsePhase(
    Map<String, dynamic> json, {
    required Set<String> phaseKeys,
  }) {
    final key = _optionalString(json['key']);
    if (key == null || !phaseKeys.contains(key)) return null;

    final rawTasks = json['optional_tasks'] ?? json['optionalTasks'];
    final tasks = <PreparationOptionalTaskSuggestion>[];
    final seenTemplateKeys = <String>{};

    if (rawTasks is List) {
      for (final raw in rawTasks) {
        if (tasks.length >= 3) break; // 每阶段最多 3 条
        if (raw is! Map) continue;
        final task = _parseTask(Map<String, dynamic>.from(raw));
        if (task == null) continue;
        // 重复 templateKey（非空）丢弃；templateKey 为 null 不参与去重。
        if (task.templateKey != null &&
            !seenTemplateKeys.add(task.templateKey!)) {
          continue;
        }
        tasks.add(task);
      }
    }

    return PreparationPhasePersonalization(
      key: key,
      optionalTasks: tasks,
      personalizedAdvice: _optionalString(
        json['personalized_advice'] ?? json['personalizedAdvice'],
      ),
    );
  }

  static PreparationOptionalTaskSuggestion? _parseTask(
    Map<String, dynamic> json,
  ) {
    final title = _optionalString(json['title']);
    if (title == null) return null;

    final hours = _parseDouble(
      json['estimated_hours'] ?? json['estimatedHours'],
    );
    if (hours == null) return null;

    final templateKey = _optionalString(
      json['template_key'] ?? json['templateKey'],
    );

    return PreparationOptionalTaskSuggestion(
      templateKey: templateKey,
      title: title,
      estimatedHours: hours,
    );
  }

  static double? _parseDouble(Object? value) {
    return switch (value) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };
  }

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }
}
