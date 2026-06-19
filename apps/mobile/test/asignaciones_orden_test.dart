import 'package:flutter_test/flutter_test.dart';
import 'package:dems_mobile/features/asignaciones/data/asignacion_models.dart';

AsignacionItem _item(String folio, {required bool submitted, String? evalId}) {
  return AsignacionItem(
    prototipo: PrototipoSummary(id: 'p-$folio', folio: folio, nombre: folio),
    rubric: const RubricSummary(
      id: 'r1',
      nombre: 'Exhibición',
      tipo: RubricType.exhibicion,
    ),
    evaluacionId: evalId,
    submitted: submitted,
  );
}

void main() {
  group('compareFoliosNatural', () {
    test('ordena numéricamente sin padding (P-2 antes que P-10)', () {
      final folios = ['P-10', 'P-2', 'P-1', 'P-20', 'P-3'];
      folios.sort(compareFoliosNatural);
      expect(folios, ['P-1', 'P-2', 'P-3', 'P-10', 'P-20']);
    });

    test('coincide con lexicográfico cuando hay padding fijo', () {
      final folios = ['ABC010', 'ABC002', 'ABC001', 'ABC070'];
      folios.sort(compareFoliosNatural);
      expect(folios, ['ABC001', 'ABC002', 'ABC010', 'ABC070']);
    });

    test('agrupa por prefijo antes que por número', () {
      final folios = ['DSW001', 'APE010', 'APE002', 'DSW003'];
      folios.sort(compareFoliosNatural);
      expect(folios, ['APE002', 'APE010', 'DSW001', 'DSW003']);
    });
  });

  group('orderAsignaciones', () {
    test('pendientes primero, enviadas al final, folio natural en cada grupo',
        () {
      final items = [
        _item('P-10', submitted: true),
        _item('P-2', submitted: false),
        _item('P-1', submitted: true),
        _item('P-20', submitted: false, evalId: 'e1'), // en progreso = pendiente
      ];

      final ordered = orderAsignaciones(items);
      final folios = ordered.map((i) => i.prototipo.folio).toList();

      // Grupo pendiente (P-2, P-20) primero en orden natural, luego enviadas
      // (P-1, P-10) en orden natural.
      expect(folios, ['P-2', 'P-20', 'P-1', 'P-10']);
    });

    test('no muta la lista original', () {
      final items = [
        _item('P-2', submitted: true),
        _item('P-1', submitted: false),
      ];
      final original = [...items];
      orderAsignaciones(items);
      expect(items, original);
    });
  });
}
