import 'package:flutter/foundation.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  bool _isLoggedIn = false;
  String? _role;
  String? _email;
  int? _userId;

  bool get isLoggedIn => _isLoggedIn;
  String? get role => _role;
  String? get email => _email;
  int? get userId => _userId;
  bool get isAdmin => _role == 'ADMIN';

  Future<void> checkAuth() async {
    final token = await ApiService.getToken();
    if (token != null && !JwtDecoder.isExpired(token)) {
      final decoded = JwtDecoder.decode(token);
      _isLoggedIn = true;
      _role = decoded['role'];
      _userId = decoded['user_id']?.toInt();
      notifyListeners();
      // JWT не содержит email — подтягиваем с /me.
      _loadMe();
    } else {
      _isLoggedIn = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final result = await ApiService.login(email, password);
    if (result['success'] == true) {
      final token = result['token'];
      final decoded = JwtDecoder.decode(token);
      _isLoggedIn = true;
      _role = decoded['role'];
      _userId = decoded['user_id']?.toInt();
      _email = email; // мгновенно из формы — UX
      notifyListeners();
      _loadMe(); // верификация с сервера
    }
    return result;
  }

  /// Подтянуть данные через GET /me (email отсутствует в JWT).
  Future<void> _loadMe() async {
    final me = await ApiService.getMe();
    if (me == null) return;
    final newEmail = me['email'] as String?;
    final newRole = me['role'] as String?;
    if (newEmail != _email || newRole != _role) {
      _email = newEmail;
      _role = newRole ?? _role;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await ApiService.clearToken();
    _isLoggedIn = false;
    _role = null;
    _email = null;
    _userId = null;
    notifyListeners();
  }
}
