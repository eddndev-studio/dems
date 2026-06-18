import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import 'evaluacion_models.dart';

/// Resultado de [EvaluacionesRepository.createEvaluacion]: la vista del
/// servidor más si fue un replay idempotente (HTTP 200) en lugar de una
/// creación nueva (HTTP 201).
class CreateEvaluacionResult {
  const CreateEvaluacionResult({required this.view, required this.replayed});
  final EvaluacionView view;
  final bool replayed;
}

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

  /// Crea (o reproduce de forma idempotente) una evaluación.
  ///
  /// El backend responde `201` cuando la crea por primera vez y `200` cuando
  /// reproduce una ya existente con el mismo `(jurado, client_id)`. El flag
  /// [CreateEvaluacionResult.replayed] expone esa diferencia para que el sync
  /// pueda empujar los scores locales que aún no llegaron al servidor.
  ///
  /// El cliente manda SIEMPRE el set completo de [scores] (el server hace
  /// replace-all), por lo que no hay merge parcial que perder en una creación.
  Future<CreateEvaluacionResult> createEvaluacion({
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
      return CreateEvaluacionResult(
        view: EvaluacionView.fromJson(res.data!),
        replayed: res.statusCode == 200,
      );
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
      return EvaluacionConflict(
        _detail(e.response?.data) ?? 'Conflicto',
        code: _code(e.response?.data),
      );
    }
    if (status == 422) {
      return EvaluacionValidation(_detail(e.response?.data) ?? 'Validación');
    }
    return EvaluacionUnexpected(e.message ?? 'HTTP $status');
  }

  /// Extrae el detalle de error del body. El API responde `{ "error": msg }`;
  /// toleramos también `message`/`detail` por robustez.
  String? _detail(dynamic body) {
    if (body is Map<String, dynamic>) {
      final m = body['error'] ?? body['message'] ?? body['detail'];
      if (m != null) return m.toString();
      return body.toString();
    }
    return body?.toString();
  }

  /// Extrae el código máquina (`{ "code": "..." }`) de los 409 de evaluación.
  /// Es `null` si el backend no lo manda (el sync cae al fallback por substring).
  String? _code(dynamic body) {
    if (body is Map<String, dynamic>) {
      final c = body['code'];
      if (c is String && c.isNotEmpty) return c;
    }
    return null;
  }
}

final evaluacionesRepositoryProvider =
    Provider<EvaluacionesRepository>((ref) {
  return EvaluacionesRepository(ref.watch(apiClientProvider));
});
