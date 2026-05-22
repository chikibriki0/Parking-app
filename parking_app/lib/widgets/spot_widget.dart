import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// SpotWidget — карточка одного парковочного места.
///
/// Дизайн: квадрат с большими скруглёнными углами, мягкая «лёжкая» тень
/// (в духе iOS), тонкая граница цвета бренда у «своего» места. При
/// нажатии — лёгкая анимация уменьшения масштаба (Cupertino feel).
class SpotWidget extends StatefulWidget {
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

  @override
  State<SpotWidget> createState() => _SpotWidgetState();
}

class _SpotWidgetState extends State<SpotWidget> {
  bool _pressed = false;

  Color _bg(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (widget.isMySpot) return AppTheme.primary;
    if (widget.status == 'OCCUPIED') {
      return isDark
          ? AppTheme.danger.withOpacity(0.25)
          : AppTheme.danger.withOpacity(0.12);
    }
    return isDark
        ? AppTheme.success.withOpacity(0.25)
        : AppTheme.success.withOpacity(0.14);
  }

  Color _fg(BuildContext context) {
    if (widget.isMySpot) return Colors.white;
    if (widget.status == 'OCCUPIED') return AppTheme.danger;
    return AppTheme.success;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: _bg(context),
            borderRadius: BorderRadius.circular(16),
            boxShadow: widget.isMySpot
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.30),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    )
                  ]
                : null,
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.isMySpot)
                      const Icon(Icons.directions_car_rounded,
                          color: Colors.white, size: 16),
                    Text(
                      '${widget.spotNumber}',
                      style: TextStyle(
                        color: _fg(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
