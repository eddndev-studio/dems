import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

class Env {
  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// API pública de producción (VPS2, detrás de Cloudflare + TLS).
  static const String _prod = 'https://dems.eddndev.work';

  static String get apiBaseUrl {
    // 1. Override explícito: --dart-define=API_BASE_URL=...
    if (_override.isNotEmpty) return _override;
    // 2. Builds de release → producción.
    if (kReleaseMode) return _prod;
    // 3. Debug/profile → desarrollo local.
    if (kIsWeb) return 'http://localhost:8080';
    if (Platform.isAndroid) return 'http://10.0.2.2:8080';
    return 'http://localhost:8080';
  }
}
