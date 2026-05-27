import 'package:flutter/material.dart';

import '../shared/section_placeholder.dart';

class AdminResultsPage extends StatelessWidget {
  const AdminResultsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      eyebrow: 'Administración · Resultados',
      title: 'Ranking y exportes',
      subtitle:
          'Consolida puntajes por categoría, descarga CSV y reabre evaluaciones cuando se requiera.',
      icon: Icons.leaderboard_outlined,
    );
  }
}
