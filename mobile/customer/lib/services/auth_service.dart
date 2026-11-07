import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final Map<String, dynamic> user;

  Map<String, dynamic> toJson() => {
    'token': token,
    'user': user,
  };

  factory AuthSession.fromJson(Map<String, dynamic> data) {
    final token = data['token'] ?? data['accessToken'];
    final userMap = data['user'] is Map
        ? Map<String, dynamic>.from(data['user'] as Map)
        : <String, dynamic>{};

    if (token == null || (token is String && token.trim().isEmpty)) {
      throw const FormatException('Authentication token is missing.');
    }

    return AuthSession(token: token.toString(), user: userMap);
  }
}

class AuthResult {
  const AuthResult({required this.success, required this.message, this.session});

  final bool success;
  final String message;
  final AuthSession? session;

  factory AuthResult.success({required String message, AuthSession? session}) =>
      AuthResult(success: true, message: message, session: session);

  factory AuthResult.failure({required String message}) =>
      AuthResult(success: false, message: message);
}

class AuthService {
  static const String _baseUrl = 'https://wasla-api-464a.onrender.com/api';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    return _request(
      endpoint: '/auth/login',
      payload: {
        'email': email.trim(),
        'password': password,
      },
      successMessage: 'Login successful.',
      onSuccess: (payload) => _sessionFromPayload(payload),
    );
  }

  static Future<AuthResult> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    return _request(
      endpoint: '/auth/register',
      payload: {
        'fullName': fullName.trim(),
        'name': fullName.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        'phoneNumber': phone.trim(),
        'password': password,
        'role': 'customer',
        'acceptPolicies': true,
      },
      successMessage: 'Account created successfully.',
      onSuccess: (payload) => _sessionFromPayload(payload),
    );
  }

  static Future<AuthResult> verifyEmail({
    required String email,
    required String code,
  }) async {
    return _request(
      endpoint: '/auth/verify-email',
      payload: {
        'email': email.trim(),
        'code': code.trim(),
        'otp': code.trim(),
      },
      successMessage: 'Email verified successfully.',
      onSuccess: (payload) => _sessionFromPayload(payload),
    );
  }

  static Future<AuthResult> resendCode({required String email}) async {
    return _request(
      endpoint: '/auth/resend-code',
      payload: {'email': email.trim()},
      successMessage: 'A new code has been sent.',
      onSuccess: (payload) => _sessionFromPayload(payload),
    );
  }

  static Future<AuthResult> forgotPassword({required String email}) async {
    return _request(
      endpoint: '/auth/forgot-password',
      payload: {'email': email.trim()},
      successMessage: 'Password reset instructions sent.',
      onSuccess: (payload) => _sessionFromPayload(payload),
    );
  }

  static Future<AuthResult> resetPassword({
    required String email,
    required String otp,
    required String password,
  }) async {
    return _request(
      endpoint: '/auth/reset-password',
      payload: {
        'email': email.trim(),
        'otp': otp.trim(),
        'code': otp.trim(),
        'password': password,
        'newPassword': password,
      },
      successMessage: 'Password updated successfully.',
      onSuccess: (payload) => _sessionFromPayload(payload),
    );
  }

  static Future<AuthResult> _request({
    required String endpoint,
    required Map<String, dynamic> payload,
    required String successMessage,
    required AuthSession? Function(Map<String, dynamic> payload) onSuccess,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl$endpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));

      final decoded = _decodeBody(response.body);
      final statusCode = response.statusCode;

      if (statusCode >= 200 && statusCode < 300) {
        final session = onSuccess(decoded);
        if (session != null) {
          await saveSession(session);
          return AuthResult.success(message: successMessage, session: session);
        }
        return AuthResult.success(message: successMessage);
      }

      final message = _messageFromPayload(decoded, fallback: 'Request failed ($statusCode).');
      return AuthResult.failure(message: message);
    } on http.ClientException catch (error) {
      return AuthResult.failure(
        message: 'Network error: ${error.message}. Please check your internet connection.',
      );
    } on FormatException catch (error) {
      return AuthResult.failure(message: error.message);
    } catch (error) {
      return AuthResult.failure(message: 'Unexpected error: $error');
    }
  }

  static Future<void> saveSession(AuthSession session) async {
    await _secureStorage.write(key: 'wasla_auth_token', value: session.token);
    await _secureStorage.write(
      key: 'wasla_user_data',
      value: jsonEncode(session.user),
    );
  }

  static Future<void> clearSession() async {
    await _secureStorage.delete(key: 'wasla_auth_token');
    await _secureStorage.delete(key: 'wasla_user_data');
  }

  static Future<AuthSession?> loadSession() async {
    final token = await _secureStorage.read(key: 'wasla_auth_token');
    final userData = await _secureStorage.read(key: 'wasla_user_data');
    if (token == null || token.trim().isEmpty) {
      return null;
    }

    if (userData == null || userData.trim().isEmpty) {
      return const AuthSession(token: '', user: {});
    }

    try {
      final decodedUser = jsonDecode(userData);
      if (decodedUser is Map<String, dynamic>) {
        return AuthSession(token: token, user: decodedUser);
      }
      if (decodedUser is Map) {
        return AuthSession(token: token, user: Map<String, dynamic>.from(decodedUser));
      }
      return AuthSession(token: token, user: {'name': 'Wasla User'});
    } on FormatException {
      return AuthSession(token: token, user: {'name': 'Wasla User'});
    }
  }

  static Future<bool> isAuthenticated() async {
    final session = await loadSession();
    return session != null && session.token.trim().isNotEmpty;
  }

  static Map<String, dynamic> _decodeBody(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{'message': 'Empty response from server.'};
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return {'message': decoded.toString()};
    } on FormatException {
      return {'message': body};
    }
  }

  static String _messageFromPayload(Map<String, dynamic> payload, {required String fallback}) {
    final rawMessage = payload['message'] ?? payload['error'] ?? payload['detail'];
    if (rawMessage is String && rawMessage.trim().isNotEmpty) {
      return rawMessage;
    }

    final validationErrors = payload['errors'];
    if (validationErrors is Map) {
      final firstValue = validationErrors.values.first;
      if (firstValue is List && firstValue.isNotEmpty) {
        return firstValue.first.toString();
      }
      if (firstValue is String && firstValue.trim().isNotEmpty) {
        return firstValue;
      }
    }

    return fallback;
  }

  static AuthSession? _sessionFromPayload(Map<String, dynamic> payload) {
    final dataNode = payload['data'];
    final userNode = payload['user'];
    final token = payload['token'] ?? payload['accessToken'] ?? dataNode?['token'] ?? dataNode?['accessToken'];
    final user = userNode is Map
        ? Map<String, dynamic>.from(userNode)
        : dataNode is Map && dataNode['user'] is Map
            ? Map<String, dynamic>.from(dataNode['user'] as Map)
            : <String, dynamic>{};

    if (token == null || token.toString().trim().isEmpty) {
      return null;
    }

    return AuthSession(token: token.toString(), user: user);
  }
}
