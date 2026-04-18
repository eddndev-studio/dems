import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Uppercase tracked pill that precedes major headings.
/// Small dot + text, rounded pill, hairline border — editorial rhythm.
class EyebrowTag extends StatelessWidget {
  const EyebrowTag({
    super.key,
    required this.label,
    this.dotColor,
  });

  final String label;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor ?? AppColors.accent,
              boxShadow: [
                BoxShadow(
                  color: (dotColor ?? AppColors.accent)
                      .withValues(alpha: 0.6),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.4,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
