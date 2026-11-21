import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthSession {
  const AuthSession({
    required this.token,
    this.refreshToken,
    this.expiresAt,
    required this.user,
  });

  final String token;
  final String? refreshToken;
  final DateTime? expiresAt;
  final Map<String, dynamic> user;

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());

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

  Map<String, dynamic> toJson() => {
    'token': token,
    'accessToken': token,
    if (refreshToken != null) 'refreshToken': refreshToken,
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
    'user': user,
  };

  factory AuthSession.fromJson(Map<String, dynamic> data) {
    final token = data['token'] ?? data['accessToken'];
    final refreshToken = data['refreshToken']?.toString();
    final expiresAt = DateTime.tryParse(data['expiresAt']?.toString() ?? '');
    final userMap = data['user'] is Map
        ? Map<String, dynamic>.from(data['user'] as Map)
        : <String, dynamic>{};

    if (token == null || (token is String && token.trim().isEmpty)) {
      throw const FormatException('Authentication token is missing.');
    }

    return AuthSession(
      token: token.toString(),
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      user: userMap,
    );
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
    this.details,
  });

  final String code;
  final String message;
  final String? field;
  final int? statusCode;
  final Map<String, dynamic>? details;

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

  static final ValueNotifier<bool> sessionExpired = ValueNotifier<bool>(false);
  static bool _sessionExpiredRedirectScheduled = false;

  static void markSessionExpired() {
    if (_sessionExpiredRedirectScheduled) return;
    _sessionExpiredRedirectScheduled = true;
    sessionExpired.value = true;
  }

  static void clearSessionExpiredRedirect() {
    _sessionExpiredRedirectScheduled = false;
    sessionExpired.value = false;
  }

  static Future<String>? _refreshFuture;

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
    bool allowRefresh = true,
  }) async {
    if (!authenticated) {
      final response = await _performRequest(
        method: method,
        endpoint: endpoint,
        body: body,
        bytes: bytes,
        contentType: contentType,
        query: query,
      );
      final decoded = _decodeBody(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'];
        final errorMap = error is Map ? error : const <String, dynamic>{};
        final code = errorMap['code']?.toString() ?? 'REQUEST_FAILED';
        final message =
            errorMap['message']?.toString() ?? 'The request could not be completed.';
        throw AuthenticatedApiException(
          code: code,
          field: errorMap['field']?.toString(),
          message: message,
          statusCode: response.statusCode,
        );
      }
      return decoded;
    }

    var token = await _secureStorage.read(key: 'wasla_auth_token');
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticatedApiException(
        code: 'UNAUTHENTICATED',
        message: 'Please sign in with a Customer account to continue.',
      );
    }

    var response = await _performRequest(
      method: method,
      endpoint: endpoint,
      body: body,
      bytes: bytes,
      contentType: contentType,
      query: query,
      token: token,
    );
    var decoded = _decodeBody(response.body);

    if (response.statusCode == 401 &&
        allowRefresh &&
        _errorCode(decoded) == 'TOKEN_EXPIRED') {
      try {
        token = await _refreshAccessToken();
      } on AuthenticatedApiException catch (error) {
        if (error.code == 'SESSION_ENDED') {
          await clearSession();
          markSessionExpired();
        }
        rethrow;
      }
      response = await _performRequest(
        method: method,
        endpoint: endpoint,
        body: body,
        bytes: bytes,
        contentType: contentType,
        query: query,
        token: token,
      );
      decoded = _decodeBody(response.body);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      final errorMap = error is Map<String, dynamic>
          ? error
          : (error is Map
              ? Map<String, dynamic>.from(error)
              : const <String, dynamic>{});
      final code = errorMap['code']?.toString() ?? 'REQUEST_FAILED';
      final message =
          errorMap['message']?.toString() ?? 'The request could not be completed.';
      if (response.statusCode == 401 && code == 'SESSION_ENDED') {
        await clearSession();
        markSessionExpired();
      }
      throw AuthenticatedApiException(
        code: code,
        field: errorMap['field']?.toString(),
        message: response.statusCode == 403 && code == 'ROLE_REQUIRED'
            ? 'A Customer account is required to manage shipments.'
            : message,
        statusCode: response.statusCode,
        details: errorMap,
      );
    }

    return decoded;
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
    final session = await loadSession();
    final refreshToken = session?.refreshToken;

    try {
      if (refreshToken != null && refreshToken.trim().isNotEmpty) {
        final response = await _httpClient
            .post(
              apiUri('/auth/logout'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({'refreshToken': refreshToken}),
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final decoded = _decodeBody(response.body);
          final code = _errorCode(decoded) ?? 'REQUEST_FAILED';
          if (code == 'SESSION_ENDED') {
            await clearSession();
          }
          return AuthResult.failure(
            message: _messageFromPayload(
              decoded,
              fallback: 'Logout failed.',
            ),
          );
        }
      }
    } on http.ClientException {
      // Local cleanup still happens below.
    } catch (_) {
      // Local cleanup still happens below.
    }

    await clearSession();
    clearSessionExpiredRedirect();
    return AuthResult.success(message: 'Logged out successfully.');
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
    if (session.refreshToken != null && session.refreshToken!.trim().isNotEmpty) {
      await _secureStorage.write(
        key: 'wasla_refresh_token',
        value: session.refreshToken,
      );
    }
    if (session.expiresAt != null) {
      await _secureStorage.write(
        key: 'wasla_token_expiry',
        value: session.expiresAt!.millisecondsSinceEpoch.toString(),
      );
    }
    await _secureStorage.write(
      key: 'wasla_user_data',
      value: jsonEncode(session.user),
    );
  }

  static Future<void> clearSession() async {
    await Future.wait([
      _secureStorage.delete(key: 'wasla_auth_token'),
      _secureStorage.delete(key: 'wasla_refresh_token'),
      _secureStorage.delete(key: 'wasla_token_expiry'),
      _secureStorage.delete(key: 'wasla_user_data'),
    ]);
  }

  static Future<AuthSession?> loadSession() async {
    final token = await _secureStorage.read(key: 'wasla_auth_token');
    final refreshToken = await _secureStorage.read(key: 'wasla_refresh_token');
    final expiryMillis = await _secureStorage.read(key: 'wasla_token_expiry');
    final userData = await _secureStorage.read(key: 'wasla_user_data');
    if (token == null || token.trim().isEmpty) {
      return null;
    }

    DateTime? expiresAt;
    if (expiryMillis != null && expiryMillis.trim().isNotEmpty) {
      final parsed = int.tryParse(expiryMillis);
      if (parsed != null) {
        expiresAt = DateTime.fromMillisecondsSinceEpoch(parsed);
      }
    }

    if (userData == null || userData.trim().isEmpty) {
      return AuthSession(
        token: token,
        refreshToken: refreshToken,
        expiresAt: expiresAt,
        user: const <String, dynamic>{},
      );
    }

    try {
      final decodedUser = jsonDecode(userData);
      if (decodedUser is Map<String, dynamic>) {
        return AuthSession(
          token: token,
          refreshToken: refreshToken,
          expiresAt: expiresAt,
          user: decodedUser,
        );
      }
      if (decodedUser is Map) {
        return AuthSession(
          token: token,
          refreshToken: refreshToken,
          expiresAt: expiresAt,
          user: Map<String, dynamic>.from(decodedUser),
        );
      }
      return AuthSession(
        token: token,
        refreshToken: refreshToken,
        expiresAt: expiresAt,
        user: const <String, dynamic>{},
      );
    } on FormatException {
      return AuthSession(
        token: token,
        refreshToken: refreshToken,
        expiresAt: expiresAt,
        user: const <String, dynamic>{},
      );
    }
  }

  static Future<bool> isAuthenticated() async {
    final session = await loadSession();
    return session != null && session.token.trim().isNotEmpty;
  }

  static Future<bool> hasValidSession() async {
    final session = await loadSession();
    if (session == null || session.token.trim().isEmpty) {
      return false;
    }
    if (!session.isExpired) {
      return true;
    }
    try {
      await _refreshAccessToken();
      return true;
    } on AuthenticatedApiException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> _refreshAccessToken() {
    final existing = _refreshFuture;
    if (existing != null) {
      return existing;
    }

    final future = _performRefresh();
    _refreshFuture = future;
    return future.whenComplete(() {
      if (identical(_refreshFuture, future)) {
        _refreshFuture = null;
      }
    });
  }

  static Future<String> _performRefresh() async {
    final session = await loadSession();
    final refreshToken = session?.refreshToken;
    if (refreshToken == null || refreshToken.trim().isEmpty) {
      await clearSession();
      markSessionExpired();
      throw const AuthenticatedApiException(
        code: 'SESSION_ENDED',
        message: 'Your session has ended. Please sign in again.',
      );
    }

    try {
      final response = await _httpClient
          .post(
            apiUri('/auth/refresh'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 20));
      final decoded = _decodeBody(response.body);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = _errorCode(decoded) ?? 'REQUEST_FAILED';
        if (code == 'SESSION_ENDED') {
          await clearSession();
          markSessionExpired();
        }
        throw AuthenticatedApiException(
          code: code,
          message: _messageFromPayload(
            decoded,
            fallback: 'Your session has ended. Please sign in again.',
          ),
          statusCode: response.statusCode,
        );
      }

      final refreshedSession = _sessionFromPayload(
        decoded,
        fallbackUser: session?.user,
      );
      if (refreshedSession == null) {
        throw const AuthenticatedApiException(
          code: 'INVALID_RESPONSE',
          message: 'The server returned an invalid response.',
        );
      }
      await saveSession(refreshedSession);
      return refreshedSession.token;
    } on http.ClientException {
      throw const AuthenticatedApiException(
        code: 'NETWORK_ERROR',
        message: 'Network error. Please check your internet connection.',
      );
    } on FormatException catch (error) {
      throw AuthenticatedApiException(
        code: 'INVALID_RESPONSE',
        message: 'The server returned an invalid response: ${error.message}',
      );
    }
  }

  static Future<http.Response> _performRequest({
    required String method,
    required String endpoint,
    Map<String, dynamic>? body,
    List<int>? bytes,
    String? contentType,
    Map<String, String>? query,
    String? token,
  }) async {
    final request = http.Request(method, apiUri(endpoint, query: query));
    request.headers['Accept'] = 'application/json';

    if (token != null && token.trim().isNotEmpty) {
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

    final streamed = await _httpClient
        .send(request)
        .timeout(const Duration(seconds: 30));
    return http.Response.fromStream(streamed).timeout(const Duration(seconds: 30));
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

  static String? _errorCode(Map<String, dynamic> payload) {
    final error = payload['error'];
    final errorMap = error is Map ? error : const <String, dynamic>{};
    return errorMap['code']?.toString();
  }

  static String _messageFromPayload(
    Map<String, dynamic> payload, {
    required String fallback,
  }) {
    final error = payload['error'];
    final rawMessage =
        payload['message'] ?? (error is Map ? error['message'] : error) ?? payload['detail'];
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

  static AuthSession? _sessionFromPayload(
    Map<String, dynamic> payload, {
    Map<String, dynamic>? fallbackUser,
  }) {
    final dataNode = payload['data'];
    final userNode = payload['user'] ?? dataNode?['user'];
    final token =
        payload['token'] ??
        payload['accessToken'] ??
        dataNode?['token'] ??
        dataNode?['accessToken'];
    final refreshToken =
        payload['refreshToken'] ??
        payload['refresh_token'] ??
        dataNode?['refreshToken'] ??
        dataNode?['refresh_token'];
    final expiresIn =
        payload['expiresIn'] ??
        payload['expires_in'] ??
        dataNode?['expiresIn'] ??
        dataNode?['expires_in'];

    final user = userNode is Map
        ? Map<String, dynamic>.from(userNode)
        : fallbackUser ?? <String, dynamic>{};

    if (token == null || token.toString().trim().isEmpty) {
      return null;
    }

    DateTime? expiresAt;
    if (expiresIn is num) {
      expiresAt = DateTime.now().add(Duration(seconds: expiresIn.toInt()));
    } else if (expiresIn is String) {
      final parsed = int.tryParse(expiresIn);
      if (parsed != null) {
        expiresAt = DateTime.now().add(Duration(seconds: parsed));
      }
    }

    return AuthSession(
      token: token.toString(),
      refreshToken: refreshToken?.toString(),
      expiresAt: expiresAt,
      user: user,
    );
  }
}
