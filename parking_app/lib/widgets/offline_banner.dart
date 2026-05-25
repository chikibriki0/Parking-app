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
    return Material(
      color: AppTheme.danger,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: const [
              Icon(Icons.cloud_off_rounded, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Нет соединения с сервером. Данные могут быть устаревшими.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
