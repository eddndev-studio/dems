import 'package:flutter/material.dart';

import '../shared/section_placeholder.dart';

class AdminRubricsPage extends StatelessWidget {
  const AdminRubricsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      eyebrow: 'Administración · Rúbricas',
      title: 'Plantillas de evaluación',
      subtitle:
          'Activa / desactiva rúbricas por edición. Cubre exhibición (60%) y memoria (50%).',
      icon: Icons.rule_outlined,
    );
  }
}
