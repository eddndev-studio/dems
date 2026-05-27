import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/eyebrow_tag.dart';
import '../../../shared/widgets/stagger_reveal.dart';

/// Editorial empty-state placeholder reused by admin section stubs while
/// the concrete CRUD bloque is being implemented.
class SectionPlaceholder extends StatelessWidget {
  const SectionPlaceholder({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final horizontalPadding = w >= 1100
            ? 64.0
            : w >= 760
                ? 40.0
                : 22.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            32,
            horizontalPadding,
            48,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StaggerReveal(child: EyebrowTag(label: eyebrow)),
                const SizedBox(height: 18),
                StaggerReveal(
                  delay: const Duration(milliseconds: 80),
                  child: Text(
                    title,
                    style:
                        text.displaySmall?.copyWith(fontSize: 40, height: 1.05),
                  ),
                ),
                const SizedBox(height: 10),
                StaggerReveal(
                  delay: const Duration(milliseconds: 160),
                  child: Text(
                    subtitle,
                    style: text.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                StaggerReveal(
                  delay: const Duration(milliseconds: 220),
                  child: _ComingSoonCard(icon: icon),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ComingSoonCard extends StatelessWidget {
  const _ComingSoonCard({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.32),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: AppColors.accent),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('En construcción', style: text.titleMedium),
                const SizedBox(height: 6),
                Text(
                  'Esta sección se conectará al backend en el siguiente bloque. '
                  'La cáscara responsiva ya está lista — al ramear el CRUD '
                  'concreto, sólo se reemplaza este cuerpo.',
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
