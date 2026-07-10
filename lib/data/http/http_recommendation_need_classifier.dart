import 'package:dio/dio.dart';

import '../../core/result/result.dart';
import '../../domain/entities/recommendation.dart';
import '../../domain/entities/recommendation_result.dart';
import '../../shared/utils/recommendation_need_classifier.dart';
import '../dto/api_envelope.dart';
import '../dto/route_need_dto.dart';

/// 追问路由的 HTTP 实现：`POST /api/v1/chat/route`，把判定交给后端。
///
/// 客户端不再做硬编码关键词路由（旧 `ConservativeRecommendationNeedClassifier`
/// 已退役，关键词逻辑下沉到假后端 `follow_up_routing.dart`）。真后端可自行
/// 实现更智能的路由；失败一律降级返回 false——接口契约「宁可少产卡，
/// 不阻断对话」。
class HttpRecommendationNeedClassifier implements RecommendationNeedClassifier {
  HttpRecommendationNeedClassifier(this._dio);

  final Dio _dio;

  @override
  Future<bool> needRecommendations(
    String followUp, {
    RecommendationResult? lastResult,
  }) async {
    final result = await guardApi(
      () => _dio.post<dynamic>(
        '/api/v1/chat/route',
        data: <String, dynamic>{
          'follow_up': followUp,
          if (lastResult != null)
            'last_recommendations': _recap(lastResult.recommendations),
        },
      ),
      (data) => RouteNeedResponseDto.fromJson(asJsonObject(data)).need,
    );
    // guardApi 把信封/Dio 错误全部塌缩为 Failure；按契约降级为 false。
    return result is Success<bool> ? result.data : false;
  }

  /// 取上一轮前 5 条推荐作紧凑 recap（最多取 5 条）。
  List<Map<String, dynamic>> _recap(List<Recommendation> recs) {
    return [
      for (final r in recs.take(5))
        RecommendationRecapDto.fromEntity(r).toJson(),
    ];
  }
}
