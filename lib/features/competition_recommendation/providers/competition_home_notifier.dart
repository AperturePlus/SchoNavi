import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/error/api_error_reporter.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/ids/uuid_v7.dart';
import '../../../core/result/result.dart';
import '../../../domain/entities/competition_recommendation_result.dart';
import '../../profile/providers/profile_provider.dart';

sealed class CompetitionHomeState {
  const CompetitionHomeState();
}

class CompetitionHomeIdle extends CompetitionHomeState {
  const CompetitionHomeIdle();
}

class CompetitionHomeLoading extends CompetitionHomeState {
  final String prompt;
  const CompetitionHomeLoading(this.prompt);
}

class CompetitionHomeResult extends CompetitionHomeState {
  final CompetitionRecommendationResult data;
  const CompetitionHomeResult(this.data);
}

class CompetitionHomeHistorySummary extends CompetitionHomeState {
  final String summary;
  const CompetitionHomeHistorySummary(this.summary);
}

class CompetitionHomeEmpty extends CompetitionHomeState {
  const CompetitionHomeEmpty();
}

class CompetitionHomeError extends CompetitionHomeState {
  final Object _error;
  const CompetitionHomeError(this._error);

  AppException get error =>
      _error is AppException ? _error : ValidationException(_error.toString());
  String get message => error.message;
}

class CompetitionHomeNotifier extends Notifier<CompetitionHomeState> {
  int _requestSeq = 0;
  final UuidV7 _ids = UuidV7();

  @override
  CompetitionHomeState build() => const CompetitionHomeIdle();

  void restoreResult(CompetitionRecommendationResult result) {
    _requestSeq++;
    state = CompetitionHomeResult(result);
  }

  void showHistorySummary(String summary) {
    _requestSeq++;
    state = CompetitionHomeHistorySummary(summary);
  }

  Future<void> submit(String prompt) async {
    final mySeq = ++_requestSeq;
    final requestSessionId = 'c_${_ids.generate().replaceAll('-', '')}';
    state = CompetitionHomeLoading(prompt);
    final profile = ref.read(profileProvider);
    final repo = ref.read(competitionRecommendationRepositoryProvider);
    final result = await repo.getRecommendations(
      prompt: prompt,
      profile: profile,
      sessionId: requestSessionId,
    );

    if (mySeq != _requestSeq) return;

    state = switch (result) {
      Success(:final data) =>
        data.recommendations.isEmpty
            ? const CompetitionHomeEmpty()
            : () {
                final historyResult = data.sessionId.trim().isEmpty
                    ? CompetitionRecommendationResult(
                        sessionId: requestSessionId,
                        understanding: data.understanding,
                        recommendations: data.recommendations,
                        followUpQuestions: data.followUpQuestions,
                      )
                    : data;
                unawaited(
                  ref
                      .read(historyRepositoryProvider)
                      .addFromCompetitionResult(
                        prompt: prompt,
                        result: historyResult,
                      )
                      .catchError((Object error, StackTrace stackTrace) {
                        ref
                            .read(apiErrorReporterProvider.notifier)
                            .report('竞赛推荐历史同步失败', error, stackTrace);
                      }),
                );
                return CompetitionHomeResult(data);
              }(),
      Failure(:final error) => CompetitionHomeError(error),
    };
  }

  void reset() {
    _requestSeq++;
    state = const CompetitionHomeIdle();
  }
}

final competitionHomeProvider =
    NotifierProvider<CompetitionHomeNotifier, CompetitionHomeState>(
      CompetitionHomeNotifier.new,
    );
