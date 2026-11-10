import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final Map<String, dynamic> user;

  String? get fullName {
    final name = user['fullName'] ?? user['name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();

    final firstName = user['firstName'];
    final lastName = user['lastName'];
    final combined = [
      if (firstName is String) firstName.trim(),
      if (lastName is String) lastName.trim(),
    ].where((part) => part.isNotEmpty).join(' ');
    return combined.isEmpty ? null : combined;
  }

  Map<String, dynamic> toJson() => {'token': token, 'user': user};

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
  const AuthResult({
    required this.success,
    required this.message,
    this.session,
  });

  final bool success;
  final String message;
  final AuthSession? session;

  factory AuthResult.success({required String message, AuthSession? session}) =>
      AuthResult(success: true, message: message, session: session);

  factory AuthResult.failure({required String message}) =>
      AuthResult(success: false, message: message);
}

class AuthenticatedApiException implements Exception {
  const AuthenticatedApiException({
    required this.code,
    required this.message,
    this.field,
    this.statusCode,
  });

  final String code;
  final String message;
  final String? field;
  final int? statusCode;

  @override
  String toString() => message;
}

class AuthService {
  static const String apiBaseUrl = String.fromEnvironment(
    'WASLA_API_URL',
    defaultValue: 'https://wasla-api-464a.onrender.com/api',
  );
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static http.Client _httpClient = http.Client();

  static void replaceHttpClientForTesting(http.Client client) {
    _httpClient = client;
  }

  static Uri apiUri(String endpoint, {Map<String, String>? query}) {
    final baseUri = Uri.parse(apiBaseUrl);
    return baseUri.replace(
      path: '${baseUri.path}$endpoint',
      queryParameters: query,
    );
  }

  static Future<Map<String, dynamic>> apiRequest({
    required String method,
    required String endpoint,
    Map<String, dynamic>? body,
    List<int>? bytes,
    String? contentType,
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    final request = http.Request(method, apiUri(endpoint, query: query));
    request.headers['Accept'] = 'application/json';

    if (authenticated) {
      final token = await _secureStorage.read(key: 'wasla_auth_token');
      if (token == null || token.trim().isEmpty) {
        throw const AuthenticatedApiException(
          code: 'UNAUTHENTICATED',
          message: 'Please sign in with a Customer account to continue.',
        );
      }
      request.headers['Authorization'] = 'Bearer $token';
    }

    if (bytes != null) {
      request.headers['Content-Type'] =
          contentType ?? 'application/octet-stream';
      request.bodyBytes = bytes;
    } else if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    } else if (contentType != null) {
      request.headers['Content-Type'] = contentType;
    }

    try {
      final streamed = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 30));
      final decoded = _decodeBody(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'];
        final errorMap = error is Map ? error : const <String, dynamic>{};
        final code = errorMap['code']?.toString() ?? 'REQUEST_FAILED';
        final message =
            errorMap['message']?.toString() ??
            'The request could not be completed.';
        throw AuthenticatedApiException(
          code: code,
          field: errorMap['field']?.toString(),
          message: response.statusCode == 403 && code == 'ROLE_REQUIRED'
              ? 'A Customer account is required to manage shipments.'
              : message,
          statusCode: response.statusCode,
        );
      }
      return decoded;
    } on http.ClientException catch (error) {
      throw AuthenticatedApiException(
        code: 'NETWORK_ERROR',
        message:
            'Network error: ${error.message}. Please check your internet connection.',
      );
    } on FormatException catch (error) {
      throw AuthenticatedApiException(
        code: 'INVALID_RESPONSE',
        message: 'The server returned an invalid response: ${error.message}',
      );
    } on AuthenticatedApiException {
      rethrow;
    }
  }

  static Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    return _request(
      endpoint: '/auth/login',
      payload: {'email': email.trim(), 'password': password},
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
        'email': email.trim(),
        'phone': phone.trim(),
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
      payload: {'email': email.trim(), 'code': code.trim(), 'otp': code.trim()},
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

  static Future<AuthResult> logout() async {
    try {
      final token = await _secureStorage.read(key: 'wasla_auth_token');
      if (token == null || token.trim().isEmpty) {
        return AuthResult.failure(message: 'No active session was found.');
      }

      return await _request(
        endpoint: '/auth/logout',
        payload: const {},
        successMessage: 'Logged out successfully.',
        bearerToken: token,
        onSuccess: (_) => null,
      );
    } finally {
      await clearSession();
    }
  }

  static Future<AuthResult> _request({
    required String endpoint,
    required Map<String, dynamic> payload,
    required String successMessage,
    required AuthSession? Function(Map<String, dynamic> payload) onSuccess,
    String? bearerToken,
  }) async {
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      if (bearerToken != null) {
        headers['Authorization'] = 'Bearer $bearerToken';
      }

      final response = await _httpClient
          .post(apiUri(endpoint), headers: headers, body: jsonEncode(payload))
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

      final message = _messageFromPayload(
        decoded,
        fallback: 'Request failed ($statusCode).',
      );
      return AuthResult.failure(message: message);
    } on http.ClientException catch (error) {
      return AuthResult.failure(
        message:
            'Network error: ${error.message}. Please check your internet connection.',
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
    await Future.wait([
      _secureStorage.delete(key: 'wasla_auth_token'),
      _secureStorage.delete(key: 'wasla_user_data'),
    ]);
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
        return AuthSession(
          token: token,
          user: Map<String, dynamic>.from(decodedUser),
        );
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

  static String _messageFromPayload(
    Map<String, dynamic> payload, {
    required String fallback,
  }) {
    final error = payload['error'];
    final rawMessage =
        payload['message'] ??
        (error is Map ? error['message'] : error) ??
        payload['detail'];
    if (rawMessage is String && rawMessage.trim().isNotEmpty) {
      return rawMessage;
    }

    final validationErrors = payload['errors'] ?? (error is Map ? error : null);
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
    final token =
        payload['token'] ??
        payload['accessToken'] ??
        dataNode?['token'] ??
        dataNode?['accessToken'];
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
