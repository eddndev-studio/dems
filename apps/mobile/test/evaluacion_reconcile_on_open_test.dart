import 'package:flutter_test/flutter_test.dart';

import 'package:dems_mobile/data/db/database.dart';
import 'package:dems_mobile/features/evaluaciones/application/evaluacion_controller.dart';

Evaluacione row({
  String? serverId,
  bool dirty = false,
  bool submitRequested = false,
  DateTime? submittedAt,
}) {
  final now = DateTime.utc(2026, 6, 17);
  return Evaluacione(
    id: 'L1',
    serverId: serverId,
    prototipoId: 'p1',
    templateId: 't1',
    juradoId: 'j1',
    createdAt: now,
    updatedAt: now,
    submittedAt: submittedAt,
    dirty: dirty,
    submitRequested: submitRequested,
  );
}

void main() {
  group('#8 shouldReconcileOnOpen', () {
    test('fila limpia ya creada en server → reconcilia', () {
      expect(
        EvaluacionController.shouldReconcileOnOpen(row(serverId: 'S1')),
        isTrue,
      );
    });

    test('reopen del admin (submitted local, server pondrá NULL) → reconcilia',
        () {
      // submitRequested=true PERO ya está submittedAt local: el envío sí llegó.
      expect(
        EvaluacionController.shouldReconcileOnOpen(row(
          serverId: 'S1',
          submitRequested: true,
          submittedAt: DateTime.utc(2026, 6, 17, 8),
        )),
        isTrue,
      );
    });

    test('submit OFFLINE pendiente (no llegó al server) → NO reconcilia', () {
      expect(
        EvaluacionController.shouldReconcileOnOpen(row(
          serverId: 'S1',
          submitRequested: true,
          submittedAt: null,
        )),
        isFalse,
        reason: 'no debe borrar la intención de envío aún no sincronizada',
      );
    });

    test('fila dirty → NO reconcilia (no pisar datos locales)', () {
      expect(
        EvaluacionController.shouldReconcileOnOpen(
            row(serverId: 'S1', dirty: true)),
        isFalse,
      );
    });

    test('sin serverId → NO reconcilia (nada que traer)', () {
      expect(
        EvaluacionController.shouldReconcileOnOpen(row(serverId: null)),
        isFalse,
      );
    });
  });
}
