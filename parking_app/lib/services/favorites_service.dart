import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Локальный сервис «Избранные парковки». Хранит id (или название) парковок,
/// добавленных пользователем в избранное. Используем SharedPreferences —
/// для ВКР этого хватает, ничего не отправляем на сервер.
class FavoritesService extends ChangeNotifier {
  static const _key = 'favorite_parkings_v1';
  Set<String> _ids = {};
  bool _loaded = false;

  Set<String> get ids => _ids;
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _ids = prefs.getStringList(_key)?.toSet() ?? <String>{};
    _loaded = true;
    notifyListeners();
  }

  bool contains(String id) => _ids.contains(id);

  Future<void> toggle(String id) async {
    if (_ids.contains(id)) {
      _ids.remove(id);
    } else {
      _ids.add(id);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _ids.toList());
  }
}
