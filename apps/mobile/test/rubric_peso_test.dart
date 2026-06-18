import 'package:flutter_test/flutter_test.dart';

import 'package:dems_mobile/features/admin/rubrics/data/rubric_models.dart';

void main() {
  group('RubricSummary.peso', () {
    test('parsea el campo peso del JSON', () {
      final r = RubricSummary.fromJson({
        'id': 'r1',
        'edition_id': 'e1',
        'nombre': 'Exhibición',
        'tipo': 'exhibicion',
        'descripcion': null,
        'activo': true,
        'peso': 60,
        'editable': true,
        'section_count': 2,
        'criterion_count': 5,
      });
      expect(r.peso, 60);
    });

    test('default 100 si el backend no envía peso (fixtures previas)', () {
      final r = RubricSummary.fromJson({
        'id': 'r1',
        'edition_id': 'e1',
        'nombre': 'Memoria',
        'tipo': 'memoria',
        'descripcion': null,
        'activo': true,
        'editable': false,
        'section_count': 1,
        'criterion_count': 3,
      });
      expect(r.peso, 100);
    });

    test('copyWith respeta y actualiza el peso', () {
      final r = RubricSummary.fromJson({
        'id': 'r1',
        'edition_id': 'e1',
        'nombre': 'X',
        'tipo': 'exhibicion',
        'descripcion': null,
        'activo': true,
        'peso': 60,
        'editable': true,
        'section_count': 0,
        'criterion_count': 0,
      });
      expect(r.copyWith().peso, 60);
      expect(r.copyWith(peso: 50).peso, 50);
    });
  });

  group('RubricDetail.peso', () {
    test('parsea peso y default 100', () {
      Map<String, dynamic> base(int? peso) => {
            'id': 'r1',
            'edition_id': 'e1',
            'nombre': 'X',
            'tipo': 'memoria',
            'descripcion': null,
            'activo': true,
            'peso': ?peso,
            'editable': true,
            'categorias': <String>[],
            'sections': <Map<String, dynamic>>[],
          };
      expect(RubricDetail.fromJson(base(50)).peso, 50);
      expect(RubricDetail.fromJson(base(null)).peso, 100);
    });
  });
}
