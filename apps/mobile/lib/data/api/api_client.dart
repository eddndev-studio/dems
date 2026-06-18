import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../../core/server_config.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

final apiClientProvider = Provider<Dio>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final baseUrl = ref.watch(serverConfigProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await storage.read(key: 'access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ),
  );

  // Refresh 401: ante un access token expirado, intentamos canjear el
  // refresh_token por uno nuevo y reintentamos la request original. Las
  // requests 401 concurrentes comparten un único refresh en vuelo
  // (single-flight) para no disparar N refreshes a la vez.
  dio.interceptors.add(_RefreshInterceptor(dio: dio, storage: storage));

  dio.interceptors.add(PrettyDioLogger(requestBody: true, responseBody: false));
  return dio;
});

/// Interceptor onError que renueva el access token ante un 401 y reintenta la
/// petición original. Usa un Dio "desnudo" (sin interceptores) para llamar a
/// `/auth/refresh`, evitando recursión del propio interceptor.
class _RefreshInterceptor extends Interceptor {
  _RefreshInterceptor({required Dio dio, required FlutterSecureStorage storage})
      : _dio = dio,
        _storage = storage;

  /// Dio con interceptores (el de la app) — se usa para reintentar la request
  /// original con el nuevo bearer.
  final Dio _dio;
  final FlutterSecureStorage _storage;

  /// Dio mínimo (sin interceptores) para llamar a `/auth/refresh` sin
  /// re-disparar este onError. Se crea una sola vez; reusa el mismo adapter
  /// HTTP que el Dio de la app (importante para tests y para compartir pool).
  Dio? _bare;

  /// Refresh en vuelo compartido entre 401 concurrentes (single-flight).
  Future<String?>? _inFlight;

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';

  bool _isAuthEndpoint(String path) =>
      path.contains('/auth/refresh') || path.contains('/auth/login');

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    final options = err.requestOptions;

    final shouldTryRefresh = response?.statusCode == 401 &&
        !_isAuthEndpoint(options.path) &&
        options.extra['__retried__'] != true;

    if (!shouldTryRefresh) {
      handler.next(err);
      return;
    }

    final newAccess = await _refreshAccessToken();
    if (newAccess == null) {
      // Refresh falló → sesión inválida. Limpiamos tokens (logout efectivo);
      // el resto del estado de auth lo resuelve la app en el siguiente arranque
      // o al detectar la ausencia de tokens.
      await _clearTokens();
      handler.next(err);
      return;
    }

    // Reintenta la request original una sola vez, con el nuevo bearer.
    try {
      final retried = await _dio.fetch<dynamic>(
        options
          ..headers['Authorization'] = 'Bearer $newAccess'
          ..extra['__retried__'] = true,
      );
      handler.resolve(retried);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// Devuelve un access token fresco o `null` si el refresh falló. Comparte un
  /// único Future entre llamadas concurrentes.
  Future<String?> _refreshAccessToken() {
    return _inFlight ??= _doRefresh().whenComplete(() => _inFlight = null);
  }

  /// Dio sin interceptores que comparte el adapter HTTP del Dio de la app.
  Dio _bareDio() {
    final bare = _bare ??= Dio(BaseOptions(
      baseUrl: _dio.options.baseUrl,
      connectTimeout: _dio.options.connectTimeout,
      receiveTimeout: _dio.options.receiveTimeout,
      headers: {'Accept': 'application/json'},
    ));
    // Mantener sincronizados baseUrl y adapter (el servidor es configurable en
    // runtime y los tests inyectan un adapter en _dio).
    bare.options.baseUrl = _dio.options.baseUrl;
    bare.httpClientAdapter = _dio.httpClientAdapter;
    return bare;
  }

  Future<String?> _doRefresh() async {
    final refreshToken = await _storage.read(key: _kRefresh);
    if (refreshToken == null) return null;

    try {
      final res = await _bareDio().post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final data = res.data;
      if (data == null) return null;
      final access = data['access_token'] as String?;
      final refresh = data['refresh_token'] as String?;
      if (access == null || refresh == null) return null;
      // Persistimos ambos: el backend rota también el refresh token.
      await _storage.write(key: _kAccess, value: access);
      await _storage.write(key: _kRefresh, value: refresh);
      return access;
    } on DioException {
      return null;
    }
  }

  Future<void> _clearTokens() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }
}
