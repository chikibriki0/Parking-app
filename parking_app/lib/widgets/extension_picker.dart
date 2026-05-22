import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ExtensionOption {
  final String label;
  final Duration duration;
  const ExtensionOption(this.label, this.duration);
}

const List<ExtensionOption> kExtensionOptions = [
  ExtensionOption('+ 15 минут', Duration(minutes: 15)),
  ExtensionOption('+ 30 минут', Duration(minutes: 30)),
  ExtensionOption('+ 1 час', Duration(hours: 1)),
  ExtensionOption('+ 2 часа', Duration(hours: 2)),
];

/// Bottom sheet «Продлить парковку»: список вариантов и кнопка действия.
Future<ExtensionOption?> showExtensionPicker(
  BuildContext context, {
  required DateTime? currentExpires,
}) {
  return showModalBottomSheet<ExtensionOption>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _ExtensionSheet(currentExpires: currentExpires),
  );
}

class _ExtensionSheet extends StatefulWidget {
  final DateTime? currentExpires;
  const _ExtensionSheet({required this.currentExpires});

  @override
  State<_ExtensionSheet> createState() => _ExtensionSheetState();
}

class _ExtensionSheetState extends State<_ExtensionSheet> {
  ExtensionOption _selected = kExtensionOptions[2]; // +1 час по умолчанию

  String _formatNewEnd() {
    final base = widget.currentExpires ?? DateTime.now();
    final newEnd = base.add(_selected.duration);
    final hh = newEnd.hour.toString().padLeft(2, '0');
    final mm = newEnd.minute.toString().padLeft(2, '0');
    return 'до $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 5,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppTheme.separator,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Text(
              'Продление парковки',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Выберите, на сколько продлить бронь.',
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
                  for (int i = 0; i < kExtensionOptions.length; i++) ...[
                    InkWell(
                      onTap: () => setState(() => _selected = kExtensionOptions[i]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        child: Row(
                          children: [
                            Icon(
                              kExtensionOptions[i].label == _selected.label
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: kExtensionOptions[i].label == _selected.label
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary,
                              size: 22,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                kExtensionOptions[i].label,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: kExtensionOptions[i].label == _selected.label
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: kExtensionOptions[i].label == _selected.label
                                      ? AppTheme.primary
                                      : AppTheme.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (i < kExtensionOptions.length - 1)
                      const Padding(
                        padding: EdgeInsets.only(left: 20, right: 20),
                        child: Divider(height: 0.5),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded,
                      color: AppTheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Новое окончание: ${_formatNewEnd()}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _selected),
                child: Text('Продлить ${_selected.label}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
