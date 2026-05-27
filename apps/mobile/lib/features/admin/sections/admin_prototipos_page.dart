import 'package:flutter/material.dart';

import '../shared/section_placeholder.dart';

class AdminPrototiposPage extends StatelessWidget {
  const AdminPrototiposPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      eyebrow: 'Administración · Prototipos',
      title: 'Catálogo de prototipos',
      subtitle:
          'Registra prototipos por edición, vincula categorías y asigna integrantes.',
      icon: Icons.inventory_2_outlined,
    );
  }
}
