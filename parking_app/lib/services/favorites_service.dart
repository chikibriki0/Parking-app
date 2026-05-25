import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Локальный сервис «Избранные парковки». Хранит id (или название) парковок,
/// добавленных пользователем в избранное. Используем SharedPreferences —
/// для ВКР этого хватает, ничего не отправляем на сервер.
///
/// Ключ зависит от userId — иначе при выходе из аккаунта и входе под
/// другим пользователем тот видит чужое избранное.
class FavoritesService extends ChangeNotifier {
  static const _legacyKey = 'favorite_parkings_v1';
  int? _userId;
  Set<String> _ids = {};
  bool _loaded = false;

  Set<String> get ids => _ids;
  bool get loaded => _loaded;

  String _keyFor(int? userId) =>
      userId == null ? _legacyKey : 'favorite_parkings_u${userId}_v1';

  /// Привязать сервис к конкретному пользователю (вызывается после login).
  /// Если userId == null — гостевой режим (общий ключ).
  Future<void> bindUser(int? userId) async {
    _userId = userId;
    final prefs = await SharedPreferences.getInstance();
    _ids = prefs.getStringList(_keyFor(userId))?.toSet() ?? <String>{};
    _loaded = true;
    notifyListeners();
  }

  /// Сброс при logout — больше не показываем избранное предыдущего юзера.
  void clear() {
    _userId = null;
    _ids = {};
    notifyListeners();
  }

  /// Legacy-метод для совместимости со старым main.dart (грузит без userId).
  /// После первого login будет переопределён через bindUser().
  Future<void> load() => bindUser(null);

  bool contains(String id) => _ids.contains(id);

  Future<void> toggle(String id) async {
    if (_ids.contains(id)) {
      _ids.remove(id);
    } else {
      _ids.add(id);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyFor(_userId), _ids.toList());
  }
}
