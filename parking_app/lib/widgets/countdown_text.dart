import 'dart:async';

import 'package:flutter/material.dart';

/// CountdownText — тикающий обратный отсчёт.
///
/// Виджет держит у себя локальный `Timer.periodic(1 s)` и пересобирает
/// **только себя** — родительский экран при этом не ребилдится каждую
/// секунду. Это сильно снижает нагрузку на UI-поток на слабых телефонах.
class CountdownText extends StatefulWidget {
  /// Момент, до которого считаем (UTC или local — не важно, считаем разницу
  /// с `DateTime.now()`).
  final DateTime? expires;

  /// Стиль текста.
  final TextStyle? style;

  /// Сколько ноликов хранить (true: HH:MM:SS, false: MM:SS если < часа).
  final bool alwaysShowHours;

  const CountdownText({
    super.key,
    required this.expires,
    this.style,
    this.alwaysShowHours = true,
  });

  @override
  State<CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<CountdownText> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _format() {
    final expires = widget.expires;
    if (expires == null) return '—';
    var left = expires.difference(DateTime.now());
    if (left.isNegative) left = Duration.zero;
    final h = left.inHours;
    final m = left.inMinutes % 60;
    final s = left.inSeconds % 60;
    if (!widget.alwaysShowHours && h == 0) {
      return '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Text(_format(), style: widget.style);
  }
}
