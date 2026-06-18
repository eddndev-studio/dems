import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

/// Nombre del archivo de la BD cifrada. Es distinto del antiguo `dems.sqlite`
/// (sin cifrar): una BD previa en texto plano NO se migra automáticamente —
/// abrirla con SQLCipher fallaría. Como aún no hay despliegue masivo, está OK
/// arrancar con una BD nueva cifrada; la antigua simplemente queda huérfana y
/// hacemos un borrado best-effort (ver _deleteLegacyPlaintextDb). Si en el
/// futuro hiciera falta migrar datos, habría que hacer `ATTACH ... KEY ...` +
/// `sqlcipher_export` explícito.
const _kDbFile = 'dems_encrypted.sqlite';
const _kLegacyDbFile = 'dems.sqlite';

/// Clave en FlutterSecureStorage donde guardamos la passphrase de la BD.
const _kDbKey = 'db_key';

DatabaseConnection openConnection() {
  return DatabaseConnection(
    LazyDatabase(() async {
      // Apunta al sqlite3 de SQLCipher (no al sqlite3 normal). Debe hacerse
      // ANTES de abrir cualquier conexión. Sólo forzamos el override en las
      // plataformas donde conocemos con certeza la ubicación de los símbolos:
      //  - Android: dlopen de `libsqlcipher.so` (con workaround para 6.0.1).
      //  - iOS/macOS: SQLCipher se enlaza estáticamente en el proceso.
      // En Windows/Linux, sqlcipher_flutter_libs bundlea su propio `sqlite3`
      // (DLL/.so junto al ejecutable) y el resolver por defecto de
      // `package:sqlite3` ya lo encuentra; `DynamicLibrary.process()` NO sirve
      // ahí (Windows sólo ve el EXE), así que no lo tocamos.
      await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
      if (Platform.isAndroid) {
        open.overrideForAll(openCipherOnAndroid);
      } else if (Platform.isIOS || Platform.isMacOS) {
        open.overrideForAll(DynamicLibrary.process);
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, _kDbFile));
      final key = await _databaseKey();

      await _deleteLegacyPlaintextDb(dir.path);

      // #17 (crash-loop): si la passphrase de FlutterSecureStorage se perdió o
      // rotó, PRAGMA key con clave nueva sobre el archivo cifrado viejo hace que
      // la 1a query lance "file is not a database (26)" en CADA arranque, sin
      // recuperación. Sondeamos la apertura ANTES de devolver el NativeDatabase;
      // si la clave no abre el archivo, lo borramos (+ -wal/-shm) y recreamos
      // desde cero. Pérdida aceptable de datos no sincronizados (igual que la BD
      // legacy). Un probe separado evita lanzar dentro del `setup` de
      // NativeDatabase (eso dejaría el LazyDatabase sin recuperación posible).
      _recoverIfKeyMismatch(file, key);

      return NativeDatabase(
        file,
        setup: (raw) {
          // PRAGMA key debe ejecutarse antes de cualquier otra operación; si la
          // clave no coincide con la del archivo, las lecturas fallarán.
          // Se escapa la comilla simple por seguridad del literal SQL.
          final escaped = key.replaceAll("'", "''");
          raw.execute("PRAGMA key = '$escaped';");

          // Verifica que la librería cargada sea realmente SQLCipher. No es
          // fatal: en una plataforma donde se cargara un sqlite3 SIN cifrado,
          // preferimos degradar a "sin cifrado pero funcional" que dejar la app
          // sin arrancar. En Android/iOS/macOS (los targets de release reales)
          // el override garantiza SQLCipher.
          try {
            final cipherVersion = raw.select('PRAGMA cipher_version;');
            if (cipherVersion.isEmpty) {
              debugPrint(
                'AVISO: SQLCipher no disponible en esta plataforma; la BD '
                'local NO quedará cifrada.',
              );
            }
          } catch (_) {
            debugPrint(
              'AVISO: no se pudo verificar SQLCipher (PRAGMA cipher_version).',
            );
          }
        },
      );
    }),
  );
}

/// Código de resultado SQLite `SQLITE_NOTADB` (26): "file is not a database".
/// Es lo que devuelve SQLCipher cuando la clave no descifra el header del
/// archivo (passphrase perdida/rotada). Ver https://sqlite.org/rescode.html.
const _kSqliteNotADb = 26;

/// #17: sonda la BD cifrada con la clave actual. Si abrir + `PRAGMA key` + una
/// query mínima falla porque la clave no descifra el archivo (NOTADB / "file is
/// not a database"), borra la BD (+ -wal/-shm) para que el siguiente open la
/// recree limpia. Sólo borra ante un error de cifrado: errores transitorios o
/// de bloqueo NO disparan el borrado (no queremos perder datos buenos).
void _recoverIfKeyMismatch(File file, String key) {
  if (!file.existsSync()) return; // BD nueva: nada que recuperar.

  Database? probe;
  try {
    probe = sqlite3.open(file.path);
    final escaped = key.replaceAll("'", "''");
    probe.execute("PRAGMA key = '$escaped';");
    // La 1a operación real es la que valida la clave contra el header cifrado.
    probe.select('SELECT count(*) FROM sqlite_master;');
    // OK: la clave abre el archivo. No tocamos nada.
  } on SqliteException catch (e) {
    final notADb = e.resultCode == _kSqliteNotADb ||
        e.message.toLowerCase().contains('file is not a database');
    if (notADb) {
      debugPrint(
        'AVISO: la BD cifrada no abre con la clave actual (passphrase '
        'perdida/rotada); se recrea desde cero. Se pierden datos no '
        'sincronizados.',
      );
      _deleteEncryptedDb(file);
    } else {
      // Error transitorio (p.ej. bloqueo): NO borramos; dejamos que el open
      // real lo reintente/propague.
      debugPrint('AVISO: probe de BD cifrada falló (no NOTADB): ${e.message}');
    }
  } catch (e) {
    // Cualquier otro fallo del probe: best-effort, no borramos.
    debugPrint('AVISO: probe de BD cifrada falló: $e');
  } finally {
    probe?.dispose();
  }
}

/// Borra (best-effort) el archivo de la BD cifrada y sus sidecars WAL/SHM.
void _deleteEncryptedDb(File file) {
  for (final path in [file.path, '${file.path}-wal', '${file.path}-shm']) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // best-effort.
    }
  }
}

/// Borra (best-effort) la BD antigua sin cifrar. No se migra: la app arranca
/// con una BD nueva cifrada. Cualquier error se ignora (puede no existir).
Future<void> _deleteLegacyPlaintextDb(String dirPath) async {
  for (final name in [
    _kLegacyDbFile,
    '$_kLegacyDbFile-wal',
    '$_kLegacyDbFile-shm',
  ]) {
    try {
      final f = File(p.join(dirPath, name));
      if (f.existsSync()) await f.delete();
    } catch (_) {
      // best-effort: ignoramos fallos de borrado.
    }
  }
}

/// Lee la passphrase de la BD desde el almacenamiento seguro; la genera de
/// forma aleatoria la primera vez (256 bits en hex).
Future<String> _databaseKey() async {
  const storage = FlutterSecureStorage();
  final existing = await storage.read(key: _kDbKey);
  if (existing != null && existing.isNotEmpty) return existing;
  final generated = _randomKeyHex();
  await storage.write(key: _kDbKey, value: generated);
  return generated;
}

String _randomKeyHex() {
  final rng = Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
