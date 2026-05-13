import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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
        _statCard('Всего', '$total', AppTheme.primary, Icons.grid_view_rounded),
        const SizedBox(width: 10),
        _statCard('Свободно', '$free', AppTheme.success, Icons.check_circle_outline_rounded),
        const SizedBox(width: 10),
        _statCard('Занято', '$occupied', AppTheme.danger, Icons.cancel_outlined),
      ],
    );
  }

  Widget _statCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white.withOpacity(0.85), size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 24,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}