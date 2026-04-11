import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SpotWidget extends StatelessWidget {
  final int spotNumber;
  final String status;
  final bool isMySpot;
  final VoidCallback onTap;

  const SpotWidget({
    super.key,
    required this.spotNumber,
    required this.status,
    required this.isMySpot,
    required this.onTap,
  });

  Color get _color {
    if (isMySpot) return AppTheme.mySpot;
    if (status == 'OCCUPIED') return AppTheme.danger;
    return AppTheme.success;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: _color,
          borderRadius: BorderRadius.circular(14),
          border: isMySpot
              ? Border.all(color: AppTheme.primaryDark, width: 2.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: _color.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isMySpot)
              const Icon(Icons.directions_car_rounded,
                  color: Colors.white, size: 18),
            Text(
              '$spotNumber',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}