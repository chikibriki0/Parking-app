import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// NavigationService — открывает внешнюю карту/навигатор с маршрутом
/// до указанной точки.
///
/// Стратегия: пробуем по очереди Яндекс.Карты → Google Maps → универсальный
/// geo:-URI. Первая установленная на устройстве выиграет.
class NavigationService {
  static Future<void> openRoute({
    required BuildContext context,
    required double lat,
    required double lon,
    required String label,
  }) async {
    final candidates = <Uri>[
      // 1) Яндекс.Карты — лучший выбор для РФ
      Uri.parse('yandexmaps://maps.yandex.ru/?pt=$lon,$lat&z=16&l=map'),
      Uri.parse('https://yandex.ru/maps/?rtext=~$lat,$lon&rtt=auto'),
      // 2) Google Maps — универсально на любом Android
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lon'),
      // 3) geo:URI — последняя надежда
      Uri.parse('geo:$lat,$lon?q=$lat,$lon($label)'),
    ];

    for (final uri in candidates) {
      try {
        if (await canLaunchUrl(uri)) {
          final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (ok) return;
        }
      } catch (_) {
        // пробуем следующий вариант
      }
    }

    // Ничего не сработало → пользователю показываем сообщение
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Не удалось открыть карты на устройстве'),
      ));
    }
  }
}
