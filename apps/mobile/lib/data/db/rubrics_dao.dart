import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/evaluaciones/data/evaluacion_models.dart' as models;
import 'app_database_provider.dart';
import 'database.dart';

part 'rubrics_dao.g.dart';

@DriftAccessor(
  tables: [RubricTemplates, RubricSections, RubricCriteria],
)
class RubricsDao extends DatabaseAccessor<AppDatabase> with _$RubricsDaoMixin {
  RubricsDao(super.db);

  Future<void> upsertTree(models.RubricTemplateDetail rubric) async {
    await transaction(() async {
      await (delete(rubricCriteria)
            ..where((c) => c.sectionId.isInQuery(
                  selectOnly(rubricSections)
                    ..addColumns([rubricSections.id])
                    ..where(rubricSections.templateId.equals(rubric.id)),
                )))
          .go();
      await (delete(rubricSections)
            ..where((s) => s.templateId.equals(rubric.id)))
          .go();
      await into(rubricTemplates).insertOnConflictUpdate(
        RubricTemplatesCompanion.insert(
          id: rubric.id,
          nombre: rubric.nombre,
          tipo: rubric.tipo,
          cachedAt: DateTime.now().toUtc(),
        ),
      );
      for (final s in rubric.sections) {
        await into(rubricSections).insertOnConflictUpdate(
          RubricSectionsCompanion.insert(
            id: s.id,
            templateId: rubric.id,
            nombre: s.nombre,
            orden: s.orden,
            pesoPct: Value(s.pesoPct),
          ),
        );
        for (final c in s.criteria) {
          await into(rubricCriteria).insertOnConflictUpdate(
            RubricCriteriaCompanion.insert(
              id: c.id,
              sectionId: s.id,
              texto: c.texto,
              orden: c.orden,
              maxScore: c.maxScore,
              kind: _kindToString(c.kind),
            ),
          );
        }
      }
    });
  }

  Future<models.RubricTemplateDetail?> loadTree(String templateId) async {
    final tpl = await (select(rubricTemplates)
          ..where((t) => t.id.equals(templateId)))
        .getSingleOrNull();
    if (tpl == null) return null;

    final secs = await (select(rubricSections)
          ..where((s) => s.templateId.equals(templateId))
          ..orderBy([(s) => OrderingTerm.asc(s.orden)]))
        .get();

    final sections = <models.RubricSection>[];
    for (final s in secs) {
      final crits = await (select(rubricCriteria)
            ..where((c) => c.sectionId.equals(s.id))
            ..orderBy([(c) => OrderingTerm.asc(c.orden)]))
          .get();
      sections.add(
        models.RubricSection(
          id: s.id,
          nombre: s.nombre,
          orden: s.orden,
          pesoPct: s.pesoPct,
          criteria: crits
              .map((c) => models.RubricCriterion(
                    id: c.id,
                    texto: c.texto,
                    orden: c.orden,
                    maxScore: c.maxScore,
                    kind: models.CriterionKind.fromApi(c.kind),
                  ))
              .toList(growable: false),
        ),
      );
    }

    return models.RubricTemplateDetail(
      id: tpl.id,
      nombre: tpl.nombre,
      tipo: tpl.tipo,
      sections: sections,
    );
  }
}

String _kindToString(models.CriterionKind k) => switch (k) {
      models.CriterionKind.scale => 'scale',
      models.CriterionKind.boolean => 'boolean',
      models.CriterionKind.textKey => 'text_key',
    };

final rubricsDaoProvider = Provider<RubricsDao>((ref) {
  return RubricsDao(ref.watch(appDatabaseProvider));
});
