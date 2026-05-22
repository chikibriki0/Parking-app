import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/parking_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/countdown_text.dart';
import '../widgets/extension_picker.dart';
import '../widgets/result_dialog.dart';

/// BookingsScreen — «Мои бронирования»: большая синяя карточка активной
/// парковки с обратным отсчётом + список истории.
class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  // Таймер обратного отсчёта не нужен на уровне экрана — он изолирован
  // в виджете CountdownText, чтобы не ребилдить весь экран каждую секунду.

  Future<void> _extend() async {
    final parking = context.read<ParkingProvider>();
    final option = await showExtensionPicker(context,
        currentExpires: parking.myExpiresAt);
    if (option == null || !mounted) return;

    final result = await parking.extendParking(duration: option.duration);
    if (!mounted) return;
    if (result['success'] == true) {
      await showResultDialog(
        context,
        kind: ResultDialogKind.success,
        title: 'Парковка продлена',
        message: 'Бронь продлена ${option.label.toLowerCase()}.',
        primaryLabel: 'Хорошо',
      );
    } else {
      await showResultDialog(
        context,
        kind: ResultDialogKind.error,
        title: 'Не удалось продлить',
        message: result['message'] as String? ?? 'Попробуйте ещё раз.',
        primaryLabel: 'Понятно',
      );
    }
  }

  Future<void> _release() async {
    final parking = context.read<ParkingProvider>();
    final spotId = parking.mySpotId;
    if (spotId == null) return;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Завершить парковку?',
      message: 'Бронь будет завершена. Эту парковку всегда можно начать заново.',
      actionLabel: 'Завершить',
      actionColor: AppTheme.danger,
      actionIcon: Icons.logout_rounded,
    );
    if (confirmed != true) return;
    final result = await parking.releaseSpot(spotId);
    if (!mounted) return;
    if (result['success'] == true) {
      await showResultDialog(
        context,
        kind: ResultDialogKind.success,
        title: 'Парковка завершена',
        message: 'Спасибо, что пользуетесь сервисом!',
        primaryLabel: 'Хорошо',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final parking = context.watch<ParkingProvider>();
    final hasActive = parking.mySpotId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Мои бронирования')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (hasActive) _activeCard(parking) else _emptyActive(context),
          const SizedBox(height: 20),
          Text('История', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          if (parking.history.isEmpty)
            _emptyHistory(context)
          else
            ...parking.history.map((h) => _historyTile(h)),
        ],
      ),
    );
  }

  Widget _activeCard(ParkingProvider parking) {
    final spot = parking.mySpotId!;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary, AppTheme.primaryDark],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.35),
            blurRadius: 18, offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Активная парковка',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text('Место №$spot',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 22)),
          const SizedBox(height: 18),
          const Text('Осталось',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          CountdownText(
            expires: parking.myExpiresAt,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 38,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primary,
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _extend,
                  child: const Text('Продлить'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.18),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _release,
                  child: const Text('Завершить'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyActive(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_parking_rounded,
                color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Сейчас нет активной парковки',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                const Text(
                  'Перейдите на карту и выберите парковочное место.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyHistory(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      child: const Text(
        'История парковок пока пуста',
        style: TextStyle(color: AppTheme.textSecondary),
      ),
    );
  }

  Widget _historyTile(Map<String, dynamic> h) {
    final spotId = h['spot_id'];
    final startStr = h['start_time'] as String?;
    final endStr = h['end_time'] as String?;
    final start = startStr != null ? DateTime.tryParse(startStr)?.toLocal() : null;
    final end = endStr != null ? DateTime.tryParse(endStr)?.toLocal() : null;
    // Безопасно: пробуем русскую локаль, при ошибке — нейтральный формат.
    String dateStr;
    if (start == null) {
      dateStr = '—';
    } else {
      try {
        dateStr = DateFormat('dd MMMM, HH:mm', 'ru').format(start);
      } catch (_) {
        dateStr = DateFormat('dd.MM HH:mm').format(start);
      }
    }
    final duration = (start != null && end != null) ? end.difference(start) : null;
    final durStr = duration == null
        ? '—'
        : duration.inHours >= 1
            ? '${duration.inHours} ч ${(duration.inMinutes % 60)} мин'
            : '${duration.inMinutes} мин';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppTheme.textSecondary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.history_rounded,
                color: AppTheme.textSecondary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Место №$spotId',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(dateStr,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text(
            durStr,
            style: const TextStyle(
              color: AppTheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
