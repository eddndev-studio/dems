import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dems_mobile/features/admin/editions/application/admin_editions_controller.dart';
import 'package:dems_mobile/features/admin/editions/data/edition_models.dart';
import 'package:dems_mobile/features/admin/prototipos/application/admin_prototipos_controller.dart'
    show categoriasCatalogProvider;
import 'package:dems_mobile/features/admin/prototipos/data/prototipo_models.dart';
import 'package:dems_mobile/features/admin/rubrics/presentation/rubric_editor_page.dart';

/// Fake controller that serves a fixed edition list without touching Dio.
class _FakeEditionsController extends AdminEditionsController {
  _FakeEditionsController(this._editions);
  final List<Edition> _editions;

  @override
  Future<List<Edition>> build() async => _editions;
}

void main() {
  Widget harness(List<Edition> editions, List<Categoria> categorias) {
    return ProviderScope(
      overrides: [
        adminEditionsControllerProvider
            .overrideWith(() => _FakeEditionsController(editions)),
        categoriasCatalogProvider.overrideWith((ref) async => categorias),
      ],
      child: const MaterialApp(home: RubricEditorPage()),
    );
  }

  testWidgets('create mode: add section + criterion updates live summary',
      (tester) async {
    final edition = Edition(
      id: 'e1',
      year: 2026,
      name: 'Concurso 2026',
      active: true,
      phase: EditionPhase.preparacion,
      createdAt: DateTime(2026, 1, 1),
    );
    final cat = const Categoria(
      id: 'c1',
      slug: 'software',
      nombre: 'Software',
      orden: 1,
    );

    // Tall surface so the whole (lazy ListView) editor builds at once.
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness([edition], [cat]));
    await tester.pumpAndSettle();

    // Renders in create mode with an empty tree.
    expect(find.text('Nueva rúbrica'), findsOneWidget);
    expect(find.text('Software'), findsOneWidget); // categoría chip
    expect(find.text('Máx total: 0'), findsOneWidget);

    // Add a section → its peso + "Agregar criterio" controls appear.
    await tester.tap(find.text('Agregar sección'));
    await tester.pumpAndSettle();
    expect(find.text('Agregar criterio'), findsOneWidget);

    // Typing a section weight surfaces the live weight pill (≠100 → warning).
    await tester.enterText(find.widgetWithText(TextField, 'peso %'), '60');
    await tester.pumpAndSettle();
    expect(find.textContaining('Pesos: 60% / 100%'), findsOneWidget);

    // Add a criterion (default max_score 3) → max total recomputes.
    await tester.tap(find.text('Agregar criterio'));
    await tester.pumpAndSettle();
    expect(find.text('Máx total: 3'), findsOneWidget);

    // #20: el campo de peso de la plantilla aparece con su default 100.
    expect(
      find.textContaining('Peso (% del puntaje final combinado'),
      findsOneWidget,
    );
    // El TextField del peso muestra el valor por defecto "100".
    final pesoEditable = find.descendant(
      of: find.ancestor(
        of: find.textContaining('Peso (% del puntaje final combinado'),
        matching: find.byType(Column),
      ),
      matching: find.byType(EditableText),
    );
    expect(
      tester.widgetList<EditableText>(pesoEditable).any(
            (e) => e.controller.text == '100',
          ),
      isTrue,
    );
  });
}
