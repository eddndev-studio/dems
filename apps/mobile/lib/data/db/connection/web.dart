import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart';

/// Requiere `web/sqlite3.wasm` (release de sqlite3.dart que corresponda a
/// la versión de `sqlite3` en pubspec.lock) y `web/drift_worker.js`
/// (release de drift). Drift elige el backend disponible (OPFS, IndexedDB…)
/// según lo que soporte el navegador.
DatabaseConnection openConnection() {
  return DatabaseConnection.delayed(
    Future(() async {
      final result = await WasmDatabase.open(
        databaseName: 'dems',
        sqlite3Uri: Uri.parse('sqlite3.wasm'),
        driftWorkerUri: Uri.parse('drift_worker.js'),
      );
      if (result.missingFeatures.isNotEmpty) {
        debugPrint(
          'drift web: usando ${result.chosenImplementation}; '
          'sin soporte de ${result.missingFeatures}',
        );
      }
      return result.resolvedExecutor;
    }),
  );
}
