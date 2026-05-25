import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/parking_provider.dart';
import '../theme/app_theme.dart';

/// OfflineBanner — тонкая полоса под AppBar, которая появляется при потере
/// соединения с сервером и исчезает при восстановлении.
///
/// Слушает ParkingProvider.isOnline через context.select, чтобы НЕ
/// перерисовываться при каждом WS-событии (изменении мест) — только
/// при смене состояния online/offline.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final isOnline =
        context.select<ParkingProvider, bool>((p) => p.isOnline);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: isOnline ? const SizedBox.shrink() : const _OfflineBar(),
    );
  }
}

class _OfflineBar extends StatelessWidget {
  const _OfflineBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.danger,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppTheme.danger.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: const [
          Icon(Icons.cloud_off_rounded, color: Colors.white, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Нет соединения с сервером',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
