import '../../domain/entities/recommendation_result.dart';

/// 判定一条追问是否应触发新一轮导师推荐（产卡）。
/// 生产实现统一请求真实后端 /api/v1/chat/route。

abstract interface class RecommendationNeedClassifier {
  /// [lastResult] 为上一轮推荐结果（首轮后追问时非空）；首轮无推荐时传 null。
  /// 失败/畸形时实现应**降级返回 false**——宁可少产卡，不阻断对话。
  Future<bool> needRecommendations(
    String followUp, {
    RecommendationResult? lastResult,
  });
}
