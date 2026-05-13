import 'package:flutter/foundation.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  bool _isLoggedIn = false;
  String? _role;
  int? _userId;

  bool get isLoggedIn => _isLoggedIn;
  String? get role => _role;
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
      notifyListeners();
    }
    return result;
  }

  Future<void> logout() async {
    await ApiService.clearToken();
    _isLoggedIn = false;
    _role = null;
    _userId = null;
    notifyListeners();
  }
}