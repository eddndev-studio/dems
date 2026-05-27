import 'package:flutter/material.dart';

import '../shared/section_placeholder.dart';

class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      eyebrow: 'Administración · Usuarios',
      title: 'Gestión de usuarios',
      subtitle:
          'Alta, edición, activación y reset de contraseña de jurados y administradores.',
      icon: Icons.group_outlined,
    );
  }
}
