import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dems_mobile/core/server_config.dart';
import 'package:dems_mobile/data/api/api_client.dart';

/// Almacenamiento en memoria que imita FlutterSecureStorage para los tests
/// vía el backend de plataforma (`FlutterSecureStoragePlatform`).
class _MemStoragePlatform extends FlutterSecureStoragePlatform {
  _MemStoragePlatform(this._data);
  final Map<String, String> _data;

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      _data.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _data.clear();
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      _data[key];

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(_data);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _data[key] = value;
  }
}

/// Adapter que orquesta el escenario: el primer GET a un recurso protegido
/// devuelve 401; /auth/refresh devuelve tokens nuevos; el reintento (con el
/// nuevo bearer) devuelve 200.
class _ScriptedAdapter implements HttpClientAdapter {
  int refreshCalls = 0;
  int protectedCalls = 0;
  bool refreshSucceeds = true;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/auth/refresh')) {
      refreshCalls++;
      if (!refreshSucceeds) {
        return ResponseBody.fromString('{"error":"invalid"}', 401, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
      }
      return ResponseBody.fromString(
        jsonEncode({'access_token': 'A2', 'refresh_token': 'R2'}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    // Recurso protegido: 401 con el bearer viejo, 200 con el nuevo.
    protectedCalls++;
    final auth = options.headers['Authorization'];
    if (auth == 'Bearer A2') {
      return ResponseBody.fromString(
        jsonEncode({'ok': true, 'n': protectedCalls}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('{"error":"unauthorized"}', 401, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }
}

ProviderContainer _container() {
  return ProviderContainer(
    overrides: [
      // Storage real (const), respaldado por el platform mock en memoria.
      initialServerUrlProvider.overrideWithValue('http://localhost'),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> store;
  late FlutterSecureStorage storage;

  setUp(() {
    store = {'access_token': 'A1', 'refresh_token': 'R1'};
    FlutterSecureStoragePlatform.instance = _MemStoragePlatform(store);
    storage = const FlutterSecureStorage();
  });

  test('401 → refresh → reintento con tipado correcto (sin cast error)',
      () async {
    final container = _container();
    addTearDown(container.dispose);
    final dio = container.read(apiClientProvider);
    final adapter = _ScriptedAdapter();
    dio.httpClientAdapter = adapter;

    // El caller usa <Map<String,dynamic>>, igual que los repos reales: si el
    // reintento devolviera Response<dynamic> sin re-wrap, esto lanzaría cast.
    final res = await dio.get<Map<String, dynamic>>('/evaluaciones/x');

    expect(res.statusCode, 200);
    expect(res.data, isA<Map<String, dynamic>>());
    expect(res.data!['ok'], true);
    expect(adapter.refreshCalls, 1);
    // Tokens rotados y persistidos.
    expect(await storage.read(key: 'access_token'), 'A2');
    expect(await storage.read(key: 'refresh_token'), 'R2');
  });

  test('401 concurrentes → un solo refresh (single-flight)', () async {
    final container = _container();
    addTearDown(container.dispose);
    final dio = container.read(apiClientProvider);
    final adapter = _ScriptedAdapter();
    dio.httpClientAdapter = adapter;

    final results = await Future.wait([
      dio.get<Map<String, dynamic>>('/a'),
      dio.get<Map<String, dynamic>>('/b'),
      dio.get<Map<String, dynamic>>('/c'),
    ]);

    for (final r in results) {
      expect(r.statusCode, 200);
    }
    expect(adapter.refreshCalls, 1,
        reason: 'los 401 concurrentes comparten un único refresh');
  });

  test('refresh falla → limpia tokens (logout) y propaga el 401', () async {
    final container = _container();
    addTearDown(container.dispose);
    final dio = container.read(apiClientProvider);
    final adapter = _ScriptedAdapter()..refreshSucceeds = false;
    dio.httpClientAdapter = adapter;

    await expectLater(
      dio.get<Map<String, dynamic>>('/evaluaciones/x'),
      throwsA(isA<DioException>()),
    );
    expect(await storage.read(key: 'access_token'), isNull);
    expect(await storage.read(key: 'refresh_token'), isNull);
  });
}
