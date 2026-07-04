import 'package:dio/dio.dart';

import '../../core/result/result.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';
import '../dto/api_envelope.dart';
import '../dto/profile_dtos.dart';

class HttpProfileRepository implements ProfileRepository {
  HttpProfileRepository(this._dio);

  final Dio _dio;
  UserProfile _snapshot = const UserProfile();

  @override
  UserProfile load() => _snapshot;

  @override
  Future<UserProfile> refresh() async {
    final result = await guardApi(
      () => _dio.get<dynamic>('/api/v1/profile'),
      (data) => data == null
          ? const UserProfile()
          : UserProfileDto.fromJson(asJsonObject(data)).toEntity(),
    );
    return switch (result) {
      Success<UserProfile>(:final data) => _snapshot = data,
      Failure<UserProfile>(:final error) => throw error,
    };
  }

  @override
  Future<void> save(UserProfile profile) async {
    final saved = await guardApi(
      () => _dio.put<dynamic>(
        '/api/v1/profile',
        data: UserProfileDto.fromEntity(profile).toJson(),
      ),
      (data) => UserProfileDto.fromJson(asJsonObject(data)).toEntity(),
    );
    switch (saved) {
      case Success<UserProfile>(:final data):
        _snapshot = data;
      case Failure<UserProfile>(:final error):
        throw error;
    }
  }

  @override
  Future<void> clear() async {
    final result = await guardApi(
      () => _dio.delete<dynamic>('/api/v1/profile'),
      (_) => true,
    );
    if (result case Failure<bool>(:final error)) throw error;
    _snapshot = const UserProfile();
  }
}
