import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/calendar_date.dart';
import '../../../core/config/app_config.dart';
import '../../../core/error/api_error_reporter.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/preparation_config.dart';
import '../../../domain/entities/level_diagnosis.dart';
import '../../../domain/entities/preparation_plan.dart';
import '../../../domain/entities/user_profile.dart';
import '../../../domain/repositories/preparation_level_diagnoser.dart';
import '../../../shared/widgets/bento_tile.dart';
import '../../../shared/widgets/error_view.dart';
import '../../profile/providers/profile_provider.dart';
import '../providers/preparation_providers.dart';
import '../widgets/preparation_date_picker.dart';

/// 备赛计划创建表单（spec §8 / D11 / P2.6 / P3.4）。
///
/// 时间模型 SegmentedButton（窗口型/提交型）按 [CompetitionTimelineDefaults]
/// 预选；日期入口调用 [showPreparationDatePicker]，窗口型用 range 选比赛起止，
/// 提交型用 multiAnchor 选 DDL + 可选答辩。Step 2 水平诊断：无画像时显示两个
/// 问答（参赛经历 / 领域熟悉度）调 [preparationLevelDiagnoserProvider]，展示
/// AI 建议卡 +「接受」/「手动改档」；有画像时跳过问答展示摘要 +「重新诊断」
/// +「临时改档」。接受/重新诊断确认后写入 [LevelDiagnosisStore]。
class PreparationPlanFormPage extends ConsumerStatefulWidget {
  const PreparationPlanFormPage({super.key, required this.competition});

  final CompetitionSnapshot competition;

  @override
  ConsumerState<PreparationPlanFormPage> createState() =>
      _PreparationPlanFormPageState();
}

/// 诊断步骤内部状态机。
enum _DiagPhase {
  /// 未加载到持久化画像，展示两个问答 + 诊断按钮。
  idle,

  /// 调用 diagnoser 中。
  loading,

  /// 诊断成功，展示 AI 建议卡 + 接受 / 手动改档。
  result,

  /// 诊断失败，展示 P0 错误态 + 重试 + 手动改档（不阻断）。
  error,

  /// 持久化画像已存在，展示摘要 + 重新诊断 + 临时改档。
  persisted,

  /// 已接受诊断（结果或重新诊断后），展示简短确认 + 改档入口。
  accepted,
}

class _PreparationPlanFormPageState
    extends ConsumerState<PreparationPlanFormPage> {
  CompetitionTimelineType? _timelineType;
  DateTime? _targetDate;
  DateTime? _eventEndDate;
  DateTime? _defenseDate;
  DateTime? _registrationDeadline;
  WeeklyCommitment _weeklyCommitment = WeeklyCommitment.hours6to10;
  late ExperienceLevel _experienceLevel;
  bool _submitting = false;
  String? _dateError;

  // ── 诊断 Step 2 状态 ──────────────────────────────────────────────────
  _DiagPhase _diagPhase = _DiagPhase.idle;
  LevelDiagnosis? _persistedDiagnosis;
  LevelDiagnosisSuggestion? _suggestion;
  String? _priorExperience;
  String? _domainFamiliarity;
  bool _diagLoading = false;
  AppException? _diagError;
  PreparationConfig? _config;
  bool _initializedFromConfig = false;

  @override
  void initState() {
    super.initState();
    _experienceLevel = _experienceFromProfile(ref.read(profileProvider));
  }

  Future<void> _initializeFromConfig(PreparationConfig config) async {
    if (_initializedFromConfig) return;
    _initializedFromConfig = true;
    _config = config;
    _timelineType =
        config.defaultTimelineFor(widget.competition.id) ??
        CompetitionTimelineType.submission;
    _priorExperience = config.priorExperienceOptions.isEmpty
        ? ''
        : config.priorExperienceOptions.first;
    _domainFamiliarity = config.domainFamiliarityOptions.isEmpty
        ? ''
        : config.domainFamiliarityOptions.first;
    final key = config.normalizeCategory(widget.competition.category);
    final existing = await ref.read(levelDiagnosisStoreProvider).get(key);
    if (!mounted) return;
    if (existing != null) {
      setState(() {
        _config = config;
        _persistedDiagnosis = existing;
        _experienceLevel = existing.effectiveLevel;
        _diagPhase = _DiagPhase.persisted;
      });
    } else {
      setState(() {});
    }
  }

  ExperienceLevel _experienceFromProfile(UserProfile profile) {
    try {
      final comps = profile.competitions;
      if (comps.length >= 2 && comps.any((c) => (c.award ?? '').isNotEmpty)) {
        return ExperienceLevel.experienced;
      }
      if (comps.isNotEmpty) {
        return ExperienceLevel.intermediate;
      }
    } catch (_) {
      // 防御：任何意外都退回默认。
    }
    return ExperienceLevel.beginner;
  }

  bool get _isAiMode {
    final cfg = ref.watch(appConfigProvider);
    return cfg.dataSource == DataSource.llm && cfg.llm.isConfigured;
  }

  String get _categoryKey =>
      _config?.normalizeCategory(widget.competition.category) ??
      widget.competition.category.trim();

  CompetitionTimelineType get _effectiveTimelineType =>
      _timelineType ?? CompetitionTimelineType.submission;

  String get _dateRowLabel =>
      _effectiveTimelineType == CompetitionTimelineType.eventWindow
      ? '选择比赛起止日期'
      : '选择提交 DDL 与答辩';

  String get _dateRowValue {
    if (_targetDate == null) return '';
    if (_effectiveTimelineType == CompetitionTimelineType.eventWindow) {
      if (_eventEndDate == null) return _fmt(_targetDate!);
      return '${_fmt(_targetDate!)} – ${_fmt(_eventEndDate!)}';
    }
    if (_defenseDate == null) return 'DDL ${_fmt(_targetDate!)}';
    return 'DDL ${_fmt(_targetDate!)} · 答辩 ${_fmt(_defenseDate!)}';
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = CalendarDate.normalize(now);
    final mode = _effectiveTimelineType == CompetitionTimelineType.eventWindow
        ? PreparationDatePickerMode.range
        : PreparationDatePickerMode.multiAnchor;
    final picked = await showPreparationDatePicker(
      context: context,
      mode: mode,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 3)),
      initial: _initialSelection(),
    );
    if (picked == null) return;
    setState(() {
      if (_effectiveTimelineType == CompetitionTimelineType.eventWindow) {
        _targetDate = picked.rangeStart;
        _eventEndDate = picked.rangeEnd;
        _defenseDate = null;
      } else {
        _targetDate = picked.deadline;
        _eventEndDate = null;
        _defenseDate = picked.defense;
      }
      if (_targetDate != null &&
          _registrationDeadline != null &&
          !_registrationDeadline!.isBefore(_targetDate!)) {
        _registrationDeadline = null;
      }
      _dateError = _validate(today);
    });
  }

  PreparationDateSelection _initialSelection() {
    if (_effectiveTimelineType == CompetitionTimelineType.eventWindow) {
      return PreparationDateSelection(
        rangeStart: _targetDate,
        rangeEnd: _eventEndDate,
      );
    }
    return PreparationDateSelection(
      deadline: _targetDate,
      defense: _defenseDate,
    );
  }

  Future<void> _pickRegistrationDeadline() async {
    if (_targetDate == null) {
      setState(() => _dateError = '请先选择比赛日期');
      return;
    }
    final today = CalendarDate.normalize(DateTime.now());
    final picked = await showPreparationDatePicker(
      context: context,
      mode: PreparationDatePickerMode.single,
      firstDate: today.add(const Duration(days: 1)),
      lastDate: _targetDate!.subtract(const Duration(days: 1)),
      initial: PreparationDateSelection(
        single: _registrationDeadline ?? _targetDate!,
      ),
    );
    final value = picked?.single;
    if (value == null) return;
    setState(() => _registrationDeadline = value);
  }

  String? _validate(DateTime today) {
    if (_effectiveTimelineType == CompetitionTimelineType.eventWindow) {
      final start = _targetDate;
      final end = _eventEndDate;
      if (start == null || end == null) return '请选择比赛起止日期';
      if (end.isBefore(start)) return '结束日期不能早于开始日期';
      if (!start.isAfter(today)) return '比赛开始日期必须晚于今天';
      return null;
    }
    final deadline = _targetDate;
    if (deadline == null) return '请选择提交截止日期';
    if (!deadline.isAfter(today)) return '提交截止日期必须晚于今天';
    if (_defenseDate != null && !_defenseDate!.isAfter(deadline)) {
      return '答辩日期必须晚于提交截止日期';
    }
    return null;
  }

  // ── 诊断 Step 2 动作 ──────────────────────────────────────────────────

  Future<void> _diagnose() async {
    setState(() {
      _diagLoading = true;
      _diagPhase = _DiagPhase.loading;
    });
    final request = LevelDiagnosisRequest(
      competition: widget.competition,
      profile: ref.read(profileProvider),
      answers: [
        DiagnosisAnswer(
          questionKey: 'prior_experience',
          answer: _priorExperience ?? '',
        ),
        DiagnosisAnswer(
          questionKey: 'domain_familiarity',
          answer: _domainFamiliarity ?? '',
        ),
      ],
    );
    final result = await ref
        .read(preparationLevelDiagnoserProvider)
        .diagnose(request);
    if (!mounted) return;
    setState(() {
      _diagLoading = false;
      switch (result) {
        case Success(:final data):
          _suggestion = data;
          _diagError = null;
          _diagPhase = _DiagPhase.result;
        case Failure(:final error):
          _suggestion = null;
          _diagError = error;
          _diagPhase = _DiagPhase.error;
      }
    });
  }

  Future<void> _acceptDiagnosis() async {
    final s = _suggestion;
    if (s == null) return;
    final diagnosis = LevelDiagnosis(
      categoryKey: _categoryKey,
      diagnosedLevel: s.level,
      effectiveLevel: s.level,
      source: DiagnosisSelectionSource.aiAccepted,
      rationale: s.rationale,
      suggestion: s.suggestion,
      diagnosedAt: DateTime.now().toUtc(),
      answers: {
        'prior_experience': _priorExperience ?? '',
        'domain_familiarity': _domainFamiliarity ?? '',
      },
    );
    await ref.read(levelDiagnosisStoreProvider).save(diagnosis);
    if (!mounted) return;
    setState(() {
      _experienceLevel = s.level;
      _persistedDiagnosis = diagnosis;
      _diagPhase = _DiagPhase.accepted;
    });
  }

  /// 重新诊断：清掉本地画像快照并回到问答态。
  void _restartDiagnosis() {
    setState(() {
      _suggestion = null;
      _persistedDiagnosis = null;
      _diagPhase = _DiagPhase.idle;
    });
  }

  /// 临时改档：只改本次 effectiveLevel，不落盘。
  void _manualOverride(ExperienceLevel level) {
    setState(() => _experienceLevel = level);
  }

  Future<void> _submit() async {
    final today = CalendarDate.normalize(DateTime.now());
    final err = _validate(today);
    if (err != null) {
      setState(() => _dateError = err);
      return;
    }
    setState(() {
      _submitting = true;
      _dateError = null;
    });
    try {
      final generated = await ref
          .read(preparationPlanGeneratorProvider)
          .generate(
            competition: widget.competition,
            timelineType: _effectiveTimelineType,
            targetDate: _targetDate!,
            eventEndDate: _eventEndDate,
            defenseDate: _defenseDate,
            weeklyCommitment: _weeklyCommitment,
            experienceLevel: _experienceLevel,
            calendarToday: CalendarDate.normalize(DateTime.now()),
            profile: ref.read(profileProvider),
          );
      final plan = generated.copyWith(
        registrationDeadline: _registrationDeadline,
      );
      await ref.read(preparationPlanRepositoryProvider).save(plan);
      if (!mounted) return;
      context.pushReplacement('/preparation-plans/${plan.id}');
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ref
          .read(apiErrorReporterProvider.notifier)
          .report('生成备赛计划失败', error, stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(preparationConfigProvider);
    final config = configAsync.value;
    if (config == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('创建备赛计划')),
        body: configAsync.hasError
            ? ErrorView(
                error: normalizeAppException(
                  configAsync.error!,
                  configAsync.stackTrace,
                ),
                onRetry: () => ref.invalidate(preparationConfigProvider),
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_initializedFromConfig) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _initializeFromConfig(config);
        }
      });
    }
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('创建备赛计划')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          BentoTile(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.emoji_events_outlined,
                      size: 20,
                      color: AppColors.indigo,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.competition.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  widget.competition.category,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.inkFaint),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionLabel('时间模型'),
          _timelineSelector(cs),
          const SizedBox(height: 16),
          _sectionLabel('比赛日期'),
          BentoTile(
            onTap: _submitting ? null : _pickDate,
            child: Row(
              children: [
                const Icon(
                  Icons.event_outlined,
                  size: 20,
                  color: AppColors.indigo,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _dateRowValue.isEmpty ? _dateRowLabel : _dateRowValue,
                    style: TextStyle(
                      color: _dateRowValue.isEmpty
                          ? AppColors.inkFaint
                          : cs.onSurface,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.inkFaint,
                ),
              ],
            ),
          ),
          if (_dateError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                _dateError!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),
          _sectionLabel('报名截止（可选）'),
          BentoTile(
            onTap: _submitting ? null : _pickRegistrationDeadline,
            child: Row(
              children: [
                const Icon(
                  Icons.event_available_outlined,
                  size: 20,
                  color: AppColors.indigo,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _registrationDeadline == null
                        ? '可选，设置后可一键加入日历'
                        : _fmt(_registrationDeadline!),
                    style: TextStyle(
                      color: _registrationDeadline == null
                          ? AppColors.inkFaint
                          : cs.onSurface,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.inkFaint,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel('水平诊断'),
          _diagnosisSection(cs),
          const SizedBox(height: 16),
          _sectionLabel('每周投入'),
          _commitmentSelector(cs),
          const SizedBox(height: 16),
          _sectionLabel('当前水平'),
          _experienceSelector(cs),
          if (_isAiMode) ...[const SizedBox(height: 16), _aiNotice()],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.rocket_launch_outlined),
            label: const Text('创建备赛计划'),
          ),
        ],
      ),
    );
  }

  // ── 诊断 Step 2 UI ───────────────────────────────────────────────────

  Widget _diagnosisSection(ColorScheme cs) {
    switch (_diagPhase) {
      case _DiagPhase.persisted:
        return _persistedSummary(cs);
      case _DiagPhase.accepted:
        return _acceptedSummary(cs);
      case _DiagPhase.loading:
        return _loadingCard(cs);
      case _DiagPhase.result:
        return _resultCard(cs);
      case _DiagPhase.error:
        return _errorCard(cs);
      case _DiagPhase.idle:
        return _questionsCard(cs);
    }
  }

  Widget _questionsCard(ColorScheme cs) {
    final config = _config;
    final priorOptions = config?.priorExperienceOptions ?? const <String>[];
    final familiarityOptions =
        config?.domainFamiliarityOptions ?? const <String>[];
    return BentoTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _qaSegment(
            '参赛经历',
            _priorExperience ?? '',
            priorOptions,
            _priorExperienceLabel,
            (v) => setState(() => _priorExperience = v),
          ),
          const SizedBox(height: 12),
          _qaSegment(
            '领域熟悉度',
            _domainFamiliarity ?? '',
            familiarityOptions,
            _domainFamiliarityLabel,
            (v) => setState(() => _domainFamiliarity = v),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _diagLoading ? null : _diagnose,
            icon: const Icon(Icons.psychology_outlined, size: 18),
            label: const Text('诊断'),
          ),
          const SizedBox(height: 6),
          Text(
            '也可直接在下方「当前水平」手动改档',
            style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }

  Widget _qaSegment(
    String label,
    String value,
    List<String> options,
    String Function(String value) optionLabel,
    ValueChanged<String> onSelected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final opt in options)
              ChoiceChip(
                label: Text(optionLabel(opt)),
                selected: opt == value,
                onSelected: (_) => onSelected(opt),
              ),
          ],
        ),
      ],
    );
  }

  Widget _loadingCard(ColorScheme cs) {
    return BentoTile(
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('正在诊断…', style: TextStyle(color: cs.onSurface)),
        ],
      ),
    );
  }

  Widget _resultCard(ColorScheme cs) {
    final s = _suggestion;
    if (s == null) return const SizedBox.shrink();
    final levelLabel = _levelLabel(s.level);
    return BentoTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: AppColors.indigo),
              const SizedBox(width: 8),
              Text(
                'AI 建议：$levelLabel',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            s.rationale,
            style: TextStyle(color: cs.onSurface, fontSize: 13),
          ),
          if (s.suggestion != null && s.suggestion!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '建议：${s.suggestion}',
              style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _acceptDiagnosis,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('接受'),
              ),
              TextButton(
                onPressed: _restartDiagnosis,
                child: const Text('手动改档'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _errorCard(ColorScheme cs) {
    return BentoTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 20, color: cs.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '诊断失败，可重试或手动改档继续',
                  style: TextStyle(color: cs.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_diagError != null) ErrorView(error: _diagError),
          if (_diagError != null) const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: _diagLoading ? null : _diagnose,
                child: const Text('重试'),
              ),
              TextButton(
                onPressed: _restartDiagnosis,
                child: const Text('手动改档'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _persistedSummary(ColorScheme cs) {
    final d = _persistedDiagnosis;
    final levelLabel = d != null ? _levelLabel(d.effectiveLevel) : '';
    return BentoTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_edu_outlined,
                size: 18,
                color: AppColors.indigo,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '已按你的 ${widget.competition.category} 类画像：$levelLabel 排期',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (d != null && d.rationale.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              d.rationale,
              style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _restartDiagnosis,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新诊断'),
              ),
              TextButton(
                onPressed: null,
                child: Text(
                  '临时改档（下方「当前水平」）',
                  style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _acceptedSummary(ColorScheme cs) {
    final s = _suggestion;
    final levelLabel = s != null
        ? _levelLabel(s.level)
        : _levelLabel(_experienceLevel);
    return BentoTile(
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 18,
            color: AppColors.match,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '已采纳 AI 诊断：$levelLabel',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(onPressed: _restartDiagnosis, child: const Text('重新诊断')),
        ],
      ),
    );
  }

  static String _levelLabel(ExperienceLevel l) => switch (l) {
    ExperienceLevel.beginner => '新手',
    ExperienceLevel.intermediate => '进阶',
    ExperienceLevel.experienced => '老手',
  };

  static String _priorExperienceLabel(String value) => switch (value.trim()) {
    'beginner' => '从没参加',
    'intermediate' => '参加过未获奖',
    'experienced' => '获得校级以上奖',
    final raw => raw,
  };

  static String _domainFamiliarityLabel(String value) => switch (value.trim()) {
    'low' => '不熟',
    'medium' => '一般',
    'high' => '熟悉',
    final raw => raw,
  };

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.inkSoft,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _timelineSelector(ColorScheme cs) {
    return SegmentedButton<CompetitionTimelineType>(
      selected: {_effectiveTimelineType},
      onSelectionChanged: _submitting
          ? null
          : (s) => setState(() {
              _timelineType = s.first;
              _targetDate = null;
              _eventEndDate = null;
              _defenseDate = null;
              _dateError = null;
            }),
      segments: const [
        ButtonSegment(
          value: CompetitionTimelineType.eventWindow,
          label: Text('窗口型'),
        ),
        ButtonSegment(
          value: CompetitionTimelineType.submission,
          label: Text('提交型'),
        ),
      ],
    );
  }

  Widget _commitmentSelector(ColorScheme cs) {
    return SegmentedButton<WeeklyCommitment>(
      selected: {_weeklyCommitment},
      onSelectionChanged: _submitting
          ? null
          : (s) => setState(() => _weeklyCommitment = s.first),
      segments: const [
        ButtonSegment(value: WeeklyCommitment.hours3to5, label: Text('3-5h')),
        ButtonSegment(value: WeeklyCommitment.hours6to10, label: Text('6-10h')),
        ButtonSegment(
          value: WeeklyCommitment.hours11to15,
          label: Text('11-15h'),
        ),
        ButtonSegment(value: WeeklyCommitment.hours16plus, label: Text('16h+')),
      ],
    );
  }

  Widget _experienceSelector(ColorScheme cs) {
    return SegmentedButton<ExperienceLevel>(
      selected: {_experienceLevel},
      onSelectionChanged: _submitting ? null : (s) => _manualOverride(s.first),
      segments: const [
        ButtonSegment(value: ExperienceLevel.beginner, label: Text('新手')),
        ButtonSegment(value: ExperienceLevel.intermediate, label: Text('进阶')),
        ButtonSegment(value: ExperienceLevel.experienced, label: Text('老手')),
      ],
    );
  }

  Widget _aiNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.indigoSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.indigo),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'AI 模式会发送你的档案用于个性化建议',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.indigo.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
