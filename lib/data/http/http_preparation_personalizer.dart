import 'package:dio/dio.dart';

import '../../core/result/result.dart';
import '../../domain/repositories/preparation_personalizer.dart';
import '../dto/api_envelope.dart';
import '../dto/preparation_plan_dtos.dart';

/// HTTP 实现：`POST /api/v1/preparation-plans/generate`。
class HttpPreparationPersonalizer implements PreparationPersonalizer {
  const HttpPreparationPersonalizer(this._dio);

  final Dio _dio;

  @override
  Future<Result<PreparationPersonalizationResult>> personalize({
    required PreparationPersonalizationRequest req,
  }) {
    return guardApi(
      () => _dio.post<dynamic>(
        '/api/v1/preparation-plans/generate',
        data: req.toJson(),
      ),
      (data) => PreparationPersonalizationResultDto.fromJson(
        asJsonObject(data),
        phaseKeys: req.phaseKeys.toSet(),
      ).toEntity(),
    );
  }
}
