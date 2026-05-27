import 'package:flutter/material.dart';

import '../shared/section_placeholder.dart';

class AdminAssignmentsPage extends StatelessWidget {
  const AdminAssignmentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      eyebrow: 'Administración · Asignaciones',
      title: 'Asignaciones de jurados',
      subtitle:
          'Distribuye prototipos entre jurados según el template (exhibición / memoria).',
      icon: Icons.assignment_ind_outlined,
    );
  }
}
