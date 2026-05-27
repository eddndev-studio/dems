import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/api/api_client.dart';
import 'assignment_models.dart';

class AdminAssignmentsRepository {
  AdminAssignmentsRepository(this._dio);
  final Dio _dio;

  Future<List<Assignment>> listForPrototipo(String prototipoId) async {
    try {
      final response = await _dio
          .get<List<dynamic>>('/admin/prototipos/$prototipoId/assignments');
      return response.data!
          .cast<Map<String, dynamic>>()
          .map((j) => Assignment.fromJsonForPrototipo(prototipoId, j))
          .toList(growable: false);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw AssignmentUnexpected(e.toString());
    }
  }

  /// Returns the (created or pre-existing) assignment. The API returns 201 on
  /// create and 200 when the triple already existed; both shapes are the same.
  Future<Assignment> create({
    required String juradoId,
    required String prototipoId,
    required String templateId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/admin/assignments',
        data: {
          'jurado_id': juradoId,
          'prototipo_id': prototipoId,
          'template_id': templateId,
        },
      );
      final body = response.data!;
      // The endpoint doesn't echo the jurado profile, so the caller is
      // expected to look up the JuradoOption it just used in the picker.
      return Assignment(
        prototipoId: body['prototipo_id'] as String,
        juradoId: body['jurado_id'] as String,
        juradoFullName: '',
        juradoEmail: '',
        templateId: body['template_id'] as String,
        assignedAt: DateTime.parse(body['assigned_at'] as String),
      );
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw AssignmentUnexpected(e.toString());
    }
  }

  Future<void> delete({
    required String juradoId,
    required String prototipoId,
    required String templateId,
  }) async {
    try {
      await _dio.delete<void>(
        '/admin/assignments',
        queryParameters: {
          'jurado_id': juradoId,
          'prototipo_id': prototipoId,
          'template_id': templateId,
        },
      );
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw AssignmentUnexpected(e.toString());
    }
  }

  Future<List<JuradoOption>> listActiveJurados() async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/admin/users',
        queryParameters: {'role': 'jurado', 'is_active': true},
      );
      return response.data!
          .cast<Map<String, dynamic>>()
          .map(JuradoOption.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw AssignmentUnexpected(e.toString());
    }
  }

  Future<List<TemplateOption>> listTemplatesByEdition(String editionId) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/admin/rubric-templates',
        queryParameters: {'edition_id': editionId, 'activo': true},
      );
      return response.data!
          .cast<Map<String, dynamic>>()
          .map(TemplateOption.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw AssignmentUnexpected(e.toString());
    }
  }

  AssignmentFailure _map(DioException e) {
    final status = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const AssignmentNetwork();
    }
    final detail = _detail(e.response?.data);
    switch (status) {
      case 401:
        return const AssignmentUnauthorized();
      case 404:
        return const AssignmentNotFound();
      case 409:
        return const AssignmentHasEvaluation();
      case 400:
      case 422:
        if (detail != null) {
          if (detail.contains('not a jurado')) {
            return const AssignmentUserNotJurado();
          }
          if (detail.contains('different editions')) {
            return const AssignmentEditionMismatch();
          }
          return AssignmentValidation(detail);
        }
        return const AssignmentValidation('inválido');
      default:
        return AssignmentUnexpected(e.message ?? 'HTTP $status');
    }
  }

  String? _detail(dynamic data) {
    if (data is Map<String, dynamic>) {
      final m = data['message'];
      if (m is String) return m;
    }
    return null;
  }
}

final adminAssignmentsRepositoryProvider =
    Provider<AdminAssignmentsRepository>((ref) {
  return AdminAssignmentsRepository(ref.watch(apiClientProvider));
});
