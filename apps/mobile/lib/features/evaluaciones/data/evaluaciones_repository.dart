import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import 'evaluacion_models.dart';

class EvaluacionesRepository {
  EvaluacionesRepository(this._dio);
  final Dio _dio;

  Future<RubricTemplateDetail> fetchRubric(String templateId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/me/rubric-templates/$templateId',
      );
      return RubricTemplateDetail.fromJson(res.data!);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<EvaluacionView> fetchEvaluacion(String id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/evaluaciones/$id');
      return EvaluacionView.fromJson(res.data!);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<EvaluacionView> createEvaluacion({
    required String prototipoId,
    required String templateId,
    required String clientId,
    List<EvaluacionScore> scores = const [],
    String? observaciones,
    bool? acompanamientoAsesor,
    int? opinionPersonal,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/evaluaciones',
        data: {
          'prototipo_id': prototipoId,
          'template_id': templateId,
          'client_id': clientId,
          'observaciones': ?observaciones,
          'acompanamiento_asesor': ?acompanamientoAsesor,
          'opinion_personal': ?opinionPersonal,
          'scores': scores.map((s) => s.toJson()).toList(),
        },
      );
      return EvaluacionView.fromJson(res.data!);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<EvaluacionView> patchEvaluacion({
    required String id,
    List<EvaluacionScore>? scores,
    String? observaciones,
    bool? acompanamientoAsesor,
    int? opinionPersonal,
  }) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/evaluaciones/$id',
        data: {
          'observaciones': ?observaciones,
          'acompanamiento_asesor': ?acompanamientoAsesor,
          'opinion_personal': ?opinionPersonal,
          'scores': ?scores?.map((s) => s.toJson()).toList(),
        },
      );
      return EvaluacionView.fromJson(res.data!);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<EvaluacionView> submitEvaluacion(String id) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/evaluaciones/$id/submit',
      );
      return EvaluacionView.fromJson(res.data!);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  EvaluacionFailure _map(DioException e) {
    final status = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const EvaluacionNetworkFailure();
    }
    if (status == 403) return const EvaluacionForbidden();
    if (status == 404) return const EvaluacionNotFound();
    if (status == 409) {
      final body = e.response?.data;
      final detail = body is Map<String, dynamic>
          ? (body['message'] ?? body['detail'] ?? body.toString()).toString()
          : (body?.toString() ?? 'Conflicto');
      return EvaluacionConflict(detail);
    }
    if (status == 422) {
      final body = e.response?.data;
      final detail = body is Map<String, dynamic>
          ? (body['message'] ?? body['detail'] ?? body.toString()).toString()
          : (body?.toString() ?? 'Validación');
      return EvaluacionValidation(detail);
    }
    return EvaluacionUnexpected(e.message ?? 'HTTP $status');
  }
}

final evaluacionesRepositoryProvider =
    Provider<EvaluacionesRepository>((ref) {
  return EvaluacionesRepository(ref.watch(apiClientProvider));
});
