import 'package:drift/drift.dart';

DatabaseConnection openConnection() {
  throw UnsupportedError(
    'Esta plataforma no tiene soporte de base de datos local.',
  );
}
