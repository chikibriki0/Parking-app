import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// StatsBar — три «iOS-карточки» в одну строку. Спокойный фон цвета
/// поверхности, цветной акцент в иконке и значении. Без громких теней.
class StatsBar extends StatelessWidget {
  final Map<String, dynamic> stats;

  const StatsBar({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = stats['total_spots'] ?? 0;
    final free = stats['free'] ?? 0;
    final occupied = stats['occupied'] ?? 0;

    return Row(
      children: [
        _statCard(context, 'Всего', '$total', AppTheme.primary, Icons.grid_view_rounded),
        const SizedBox(width: 10),
        _statCard(context, 'Свободно', '$free', AppTheme.success, Icons.check_circle_rounded),
        const SizedBox(width: 10),
        _statCard(context, 'Занято', '$occupied', AppTheme.danger, Icons.do_not_disturb_on_rounded),
      ],
    );
  }

  Widget _statCard(BuildContext context, String label, String value, Color accent, IconData icon) {
    final surface = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondary;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent.withOpacity(isDark ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontSize: 26,
                    letterSpacing: -0.6,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
