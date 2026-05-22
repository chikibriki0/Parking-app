import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Один вариант длительности парковки.
class ParkingDurationOption {
  final String label;
  final Duration duration;
  const ParkingDurationOption(this.label, this.duration);
}

/// Доступные пресеты времени бронирования.
const List<ParkingDurationOption> kDurationOptions = [
  ParkingDurationOption('30 минут', Duration(minutes: 30)),
  ParkingDurationOption('1 час', Duration(hours: 1)),
  ParkingDurationOption('2 часа', Duration(hours: 2)),
  ParkingDurationOption('4 часа', Duration(hours: 4)),
  ParkingDurationOption('8 часов', Duration(hours: 8)),
  ParkingDurationOption('24 часа', Duration(hours: 24)),
];

/// Bottom sheet «На сколько забронировать?»: список с радио-выбором
/// и большой синей кнопкой подтверждения внизу.
Future<ParkingDurationOption?> showDurationPicker(
  BuildContext context, {
  required int spotNumber,
  ParkingDurationOption initial = const ParkingDurationOption(
    '2 часа',
    Duration(hours: 2),
  ),
}) {
  return showModalBottomSheet<ParkingDurationOption>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _DurationSheet(spotNumber: spotNumber, initial: initial),
  );
}

class _DurationSheet extends StatefulWidget {
  final int spotNumber;
  final ParkingDurationOption initial;

  const _DurationSheet({required this.spotNumber, required this.initial});

  @override
  State<_DurationSheet> createState() => _DurationSheetState();
}

class _DurationSheetState extends State<_DurationSheet> {
  late ParkingDurationOption _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // iOS-handle
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppTheme.separator,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Text(
              'Бронирование места №${widget.spotNumber}',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'На какое время хотите забронировать?',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
            ),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (int i = 0; i < kDurationOptions.length; i++) ...[
                    _DurationTile(
                      option: kDurationOptions[i],
                      selected: kDurationOptions[i].label == _selected.label,
                      onTap: () => setState(() => _selected = kDurationOptions[i]),
                    ),
                    if (i < kDurationOptions.length - 1)
                      const Padding(
                        padding: EdgeInsets.only(left: 20, right: 20),
                        child: Divider(height: 0.5),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _selected),
                child: Text('Забронировать на ${_selected.label}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationTile extends StatelessWidget {
  final ParkingDurationOption option;
  final bool selected;
  final VoidCallback onTap;

  const _DurationTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                option.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppTheme.primary : AppTheme.textPrimary,
                ),
              ),
            ),
            Text(
              _formatEndTime(option.duration),
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatEndTime(Duration d) {
    final end = DateTime.now().add(d);
    final hh = end.hour.toString().padLeft(2, '0');
    final mm = end.minute.toString().padLeft(2, '0');
    return 'до $hh:$mm';
  }
}
