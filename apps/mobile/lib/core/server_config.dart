import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'env.dart';

const _kServerBaseUrlKey = 'server_base_url';

// Storage propio (no el de api_client) para poder leer la URL persistida
// en main() antes de que exista el ProviderScope.
const _storage = FlutterSecureStorage();

/// Lee la URL persistida antes de montar la app. Nunca lanza: si el
/// storage está corrupto (p.ej. tras restaurar un respaldo) se cae al
/// default de compilación.
Future<String?> readPersistedServerUrl() async {
  try {
    final value = await _storage.read(key: _kServerBaseUrlKey);
    if (value == null) return null;
    return ServerEndpoint.tryParse(value)?.baseUrl;
  } catch (_) {
    return null;
  }
}

/// Valor inicial inyectado desde main() (URL persistida o default).
final initialServerUrlProvider = Provider<String>((_) => Env.apiBaseUrl);

/// Base URL efectiva del API. Cambiarla reconstruye el cliente Dio y, en
/// cascada, todos los repositorios que lo observan.
final serverConfigProvider = NotifierProvider<ServerConfigNotifier, String>(
  ServerConfigNotifier.new,
);

class ServerConfigNotifier extends Notifier<String> {
  @override
  String build() => ref.watch(initialServerUrlProvider);

  Future<void> setBaseUrl(String url) async {
    await _storage.write(key: _kServerBaseUrlKey, value: url);
    state = url;
  }

  Future<void> resetToDefault() async {
    await _storage.delete(key: _kServerBaseUrlKey);
    state = Env.apiBaseUrl;
  }
}

/// Esquema + host + puerto opcional, validados y normalizados.
/// El puerto null usa el default del esquema (80/443).
class ServerEndpoint {
  const ServerEndpoint({required this.https, required this.host, this.port});

  final bool https;
  final String host;
  final int? port;

  String get scheme => https ? 'https' : 'http';

  String get baseUrl =>
      port == null ? '$scheme://$host' : '$scheme://$host:$port';

  /// Acepta hostnames e IPv4 (`192.168.1.50`, `dems.local`). Devuelve un
  /// mensaje de error para mostrar en el formulario, o null si es válido.
  static String? validateHost(String input) {
    final host = input.trim();
    if (host.isEmpty) return 'Ingresa la IP o dominio del servidor.';
    if (host.contains('://')) {
      return 'No incluyas el esquema; elígelo arriba (HTTP/HTTPS).';
    }
    if (RegExp(r'[\s/\\@?#]').hasMatch(host)) {
      return 'La dirección no debe llevar espacios ni rutas.';
    }
    if (host.contains(':')) {
      return 'Pon el puerto en su propio campo.';
    }
    if (!RegExp(r'^[A-Za-z0-9.\-]+$').hasMatch(host)) {
      return 'Dirección inválida.';
    }
    return null;
  }

  /// Puerto vacío es válido (usa el default del esquema).
  static String? validatePort(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;
    final port = int.tryParse(raw);
    if (port == null || port < 1 || port > 65535) {
      return 'Puerto inválido (1-65535).';
    }
    return null;
  }

  /// Construye desde los campos del formulario; null si algo es inválido.
  static ServerEndpoint? fromForm({
    required bool https,
    required String host,
    required String port,
  }) {
    if (validateHost(host) != null || validatePort(port) != null) return null;
    final trimmedPort = port.trim();
    return ServerEndpoint(
      https: https,
      host: host.trim().toLowerCase(),
      port: trimmedPort.isEmpty ? null : int.parse(trimmedPort),
    );
  }

  /// Parsea una base URL guardada para prellenar el formulario.
  static ServerEndpoint? tryParse(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    final defaultPort = uri.scheme == 'https' ? 443 : 80;
    return ServerEndpoint(
      https: uri.scheme == 'https',
      host: uri.host,
      port: uri.hasPort && uri.port != defaultPort ? uri.port : null,
    );
  }
}
