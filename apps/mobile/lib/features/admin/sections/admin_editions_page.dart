import 'package:flutter/material.dart';

import '../shared/section_placeholder.dart';

class AdminEditionsPage extends StatelessWidget {
  const AdminEditionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      eyebrow: 'Administración · Ediciones',
      title: 'Ediciones del concurso',
      subtitle:
          'Define el año vigente, congela ediciones pasadas y controla qué rúbricas aplican.',
      icon: Icons.event_outlined,
    );
  }
}
