import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../data/api/api_client.dart';
import '../../rubrics/data/rubric_models.dart';
import 'result_models.dart';

class AdminResultsRepository {
  AdminResultsRepository(this._dio);
  final Dio _dio;

  Future<CategoriaResults> fetchByCategoria({
    required String slug,
    required String editionId,
    required RubricType rubricType,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/admin/results/categoria/$slug',
        queryParameters: {
          'edition_id': editionId,
          'rubric_type': rubricType.apiValue,
        },
      );
      return CategoriaResults.fromJson(response.data!);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw ResultsUnexpected(e.toString());
    }
  }

  /// Descarga el CSV completo de la edición. Devuelve el cuerpo + el filename
  /// sugerido por el header `Content-Disposition`.
  Future<CsvExport> exportCsv({
    required String editionId,
    required RubricType rubricType,
  }) async {
    try {
      final response = await _dio.get<String>(
        '/admin/results/edition/$editionId/export.csv',
        queryParameters: {'rubric_type': rubricType.apiValue},
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Accept': 'text/csv'},
        ),
      );
      final disposition =
          response.headers.value('content-disposition') ?? '';
      final match =
          RegExp(r'filename="?([^"]+)"?').firstMatch(disposition);
      final filename = match?.group(1) ??
          'resultados-${rubricType.apiValue}.csv';
      return CsvExport(body: response.data ?? '', filename: filename);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw ResultsUnexpected(e.toString());
    }
  }

  /// Persiste el CSV en disco y devuelve la ruta absoluta. En desktop intenta
  /// `~/Downloads`; en móvil cae a `ApplicationDocumentsDirectory`.
  Future<String> saveCsvToDisk(CsvExport export) async {
    try {
      Directory dir;
      if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS ||
          Platform.isWindows) {
        dir = await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      final path = p.join(dir.path, export.filename);
      final file = File(path);
      await file.writeAsString(export.body, flush: true);
      return path;
    } catch (e) {
      throw ResultsUnexpected('No se pudo guardar el archivo: $e');
    }
  }

  ResultsFailure _map(DioException e) {
    final status = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const ResultsNetwork();
    }
    final detail = _detail(e.response?.data);
    switch (status) {
      case 401:
        return const ResultsUnauthorized();
      case 404:
        return const ResultsNotFound();
      case 400:
      case 422:
        return ResultsBadRequest(detail ?? 'inválido');
      default:
        return ResultsUnexpected(e.message ?? 'HTTP $status');
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

final adminResultsRepositoryProvider =
    Provider<AdminResultsRepository>((ref) {
  return AdminResultsRepository(ref.watch(apiClientProvider));
});
