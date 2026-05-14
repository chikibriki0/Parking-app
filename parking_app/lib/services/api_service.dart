import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class ApiService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
  }

  static Future<Map<String, String>> _authHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ===== AUTH =====

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await saveToken(data['token']);
      return {'success': true, 'token': data['token']};
    } else {
      return {'success': false, 'message': 'Неверный email или пароль'};
    }
  }

  static Future<Map<String, dynamic>> register(
      String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 201) {
      return {'success': true};
    } else if (response.statusCode == 409) {
      return {
        'success': false,
        'message': 'Пользователь с таким email уже существует'
      };
    } else {
      return {'success': false, 'message': 'Ошибка регистрации'};
    }
  }

  // ===== PARKING =====

  static Future<Map<String, dynamic>?> getParkingMap() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/parking/map'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getStats() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/stats'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getMyParking() async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/my/parking'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  static Future<Map<String, dynamic>> reserveSpot(int spotId) async {
    try {
      final headers = await _authHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/reserve/$spotId'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {
        'success': false,
        'message': _mapReserveError(response.statusCode, response.body),
      };
    } catch (_) {
      return {'success': false, 'message': 'Нет соединения с сервером'};
    }
  }

  static Future<Map<String, dynamic>> releaseSpot(int spotId) async {
    try {
      final headers = await _authHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/release/$spotId'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {
        'success': false,
        'message': 'Не удалось освободить место (код ${response.statusCode})',
      };
    } catch (_) {
      return {'success': false, 'message': 'Нет соединения с сервером'};
    }
  }

  static String _mapReserveError(int code, String body) {
    final text = body.toLowerCase();
    if (code == 409) {
      if (text.contains('user already has active')) {
        return 'У вас уже есть активная парковка';
      }
      if (text.contains('spot already occupied')) {
        return 'Это место уже занято';
      }
      return 'Конфликт: место занято или у вас уже есть бронь';
    }
    if (code == 404) return 'Парковочное место не найдено';
    if (code == 401) return 'Сессия истекла — войдите заново';
    return 'Ошибка бронирования (код $code)';
  }

  static Future<List<dynamic>> getMyHistory() async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/my/history'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is List ? data : [];
      }
    } catch (e) {
      return [];
    }
    return [];
  }

  // ===== ADMIN =====

  static Future<List<dynamic>> getAdminUsers() async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/admin/users'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is List ? data : [];
      }
    } catch (e) {
      return [];
    }
    return [];
  }

  static Future<List<dynamic>> getAdminActiveSessions() async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/admin/active-sessions'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is List ? data : [];
      }
    } catch (e) {
      return [];
    }
    return [];
  }

  static Future<List<dynamic>> getAdminHistory() async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/admin/history'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is List ? data : [];
      }
    } catch (e) {
      return [];
    }
    return [];
  }

  static Future<bool> adminReleaseSpot(int spotId) async {
    try {
      final headers = await _authHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/admin/release/$spotId'),
        headers: headers,
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}