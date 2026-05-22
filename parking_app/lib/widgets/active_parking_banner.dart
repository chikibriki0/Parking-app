import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../model/parking_location.dart';
import '../providers/parking_provider.dart';
import '../screens/parking_details_screen.dart';
import '../theme/app_theme.dart';
import 'countdown_text.dart';

/// ActiveParkingBanner — горизонтальная плашка над BottomNav, видимая
/// пока есть активная бронь. Сам виджет ребилдится только при изменении
/// `mySpotId` или `myExpiresAt` (через `context.select`), а тикающий
/// обратный отсчёт изолирован в [CountdownText] — он перерисовывает только
/// себя раз в секунду, не задевая родительский экран.
class ActiveParkingBanner extends StatelessWidget {
  const ActiveParkingBanner({super.key});

  /// Находит SpotNumber + ParkingLocation для активной брони.
  ({int spotNumber, ParkingLocation? parking}) _resolveSpot(
      ParkingProvider parking, int spotId) {
    for (final zone in parking.zones) {
      final zoneName = zone['name'] as String? ?? '';
      for (final spot in (zone['spots'] as List? ?? [])) {
        if ((spot as Map)['id'] == spotId) {
          final loc = kParkings.firstWhere(
            (p) => p.zoneName == zoneName,
            orElse: () => kParkings.first,
          );
          return (
            spotNumber: spot['spot_number'] as int? ?? spotId,
            parking: loc,
          );
        }
      }
    }
    return (spotNumber: spotId, parking: null);
  }

  @override
  Widget build(BuildContext context) {
    // Слушаем ТОЛЬКО mySpotId и myExpiresAt — другие изменения провайдера
    // (карта мест, статистика, история) не вызывают ребилд этого баннера.
    final spotId =
        context.select<ParkingProvider, int?>((p) => p.mySpotId);
    if (spotId == null) return const SizedBox.shrink();

    final expires =
        context.select<ParkingProvider, DateTime?>((p) => p.myExpiresAt);

    // Для resolveSpot нам нужны zones — берём через read, без подписки.
    final parking = context.read<ParkingProvider>();
    final info = _resolveSpot(parking, spotId);
    final location = info.parking;

    final left = expires?.difference(DateTime.now()) ?? Duration.zero;
    final urgent = left.inMinutes < 10 && !left.isNegative;
    final accent = urgent ? AppTheme.warning : AppTheme.success;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: location == null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ParkingDetailsScreen(parking: location),
                    ),
                  ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withOpacity(0.6), width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.15),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'P',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Активная парковка',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${location?.title ?? 'НИУ «МЭИ»'}, место №${info.spotNumber}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      expires == null ? 'Активно' : 'Завершится через',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Только этот виджет ребилдится каждую секунду.
                    CountdownText(
                      expires: expires,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: accent,
                        letterSpacing: 0.4,
                        fontFeatures: const [
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
