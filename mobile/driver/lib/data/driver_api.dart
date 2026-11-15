import 'dart:convert';

import 'package:driver/data/driver_application.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DriverApiException implements Exception {
  const DriverApiException(this.code, this.message, {this.field, this.missing});

  final String code;
  final String message;
  final String? field;
  final List<String>? missing;

  bool get requiresLogin => const [
    'NOT_LOGGED_IN',
    'INVALID_TOKEN',
    'SESSION_ENDED',
    'UNAUTHENTICATED',
  ].contains(code);

  @override
  String toString() => message;
}

class DriverApi {
  DriverApi({http.Client? client}) : _client = client ?? http.Client();

  static final Uri _baseUri = Uri.parse(
    const String.fromEnvironment(
      'WASLA_API_URL',
      defaultValue: 'https://wasla-api-464a.onrender.com/api',
    ),
  );
  static const _accessTokenKey = 'driver.accessToken';
  static const _refreshTokenKey = 'driver.refreshToken';

  final http.Client _client;

  Future<void> saveTokens(Map<String, dynamic> response) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = response['accessToken'] as String?;
    final refreshToken = response['refreshToken'] as String?;
    if (accessToken == null || refreshToken == null) {
      throw const DriverApiException(
        'INVALID_RESPONSE',
        'تعذر حفظ جلسة الدخول.',
      );
    }
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    required bool acceptPolicies,
  }) async {
    await _publicRequest('POST', '/auth/register', {
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'password': password,
      'role': 'driver',
      'language': 'ar',
      'acceptPolicies': acceptPolicies,
    });
  }

  Future<void> verifyEmail({
    required String email,
    required String code,
  }) async {
    final response = await _publicRequest('POST', '/auth/verify-email', {
      'email': email,
      'code': code,
    });
    final roles = (response['user'] as Map?)?['roles'] as List? ?? const [];
    if (!roles.contains('driver')) {
      throw const DriverApiException(
        'ROLE_REQUIRED',
        'هذا الحساب غير مسجل كسائق.',
      );
    }
    await saveTokens(response);
  }

  Future<void> resendVerificationCode(String email) async {
    await _publicRequest('POST', '/auth/resend-code', {'email': email});
  }

  Future<void> login({required String email, required String password}) async {
    final response = await _publicRequest('POST', '/auth/login', {
      'email': email,
      'password': password,
    });
    final roles = (response['user'] as Map?)?['roles'] as List? ?? const [];
    if (!roles.contains('driver')) {
      throw const DriverApiException(
        'ROLE_REQUIRED',
        'هذا الحساب ليس حساب سائق.',
      );
    }
    await saveTokens(response);
  }

  Future<DriverApplication> getApplication() async =>
      DriverApplication.fromJson(
        await _authorized('GET', '/driver/application'),
      );

  Future<Map<String, dynamic>> getCatalog() =>
      _publicRequest('GET', '/catalog');

  Future<Map<String, dynamic>> getMe() => _authorized('GET', '/me');

  Future<Map<String, dynamic>> getPolicies() =>
      _publicRequest('GET', '/policies');

  Future<Map<String, dynamic>> acceptPolicies() =>
      _authorized('POST', '/me/accept-policies');

  Future<Map<String, dynamic>> getDriverStatus() async =>
      (await _authorized('GET', '/driver/status'))['status']
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> setOnline(Map<String, dynamic> location) async =>
      (await _authorized(
            'POST',
            '/driver/online',
            body: {'lat': location['lat'], 'lng': location['lng']},
          ))['status']
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> setOffline() async =>
      (await _authorized('POST', '/driver/offline'))['status']
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> sendLocation(
    Map<String, dynamic> location,
  ) async =>
      (await _authorized('POST', '/driver/location', body: location))['status']
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> getOffers() async =>
      _mapList((await _authorized('GET', '/driver/offers'))['offers']);

  Future<Map<String, dynamic>> acceptOffer(String offerId) async =>
      (await _authorized('POST', '/driver/offers/$offerId/accept'))['trip']
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> declineOffer(String offerId) async =>
      _mapList(
        (await _authorized(
          'POST',
          '/driver/offers/$offerId/decline',
        ))['offers'],
      );

  Future<Map<String, dynamic>?> getCurrentTrip() async {
    final trip = (await _authorized('GET', '/driver/trips/current'))['trip'];
    return (trip as Map?)?.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> updateTrip(
    String tripId,
    String action, {
    Map<String, dynamic> body = const {},
  }) async =>
      (await _authorized(
            'POST',
            '/driver/trips/$tripId/$action',
            body: body,
          ))['trip']
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> cancelTrip(String tripId, String reason) =>
      updateTrip(tripId, 'cancel', body: {'reason': reason});

  Future<Map<String, dynamic>> uploadTripPhoto(
    String tripId,
    String type,
    List<int> bytes, {
    String contentType = 'image/jpeg',
  }) async =>
      (await _authorized(
            'PUT',
            '/driver/trips/$tripId/photos/$type',
            bytes: bytes,
            contentType: contentType,
          ))['trip']
          as Map<String, dynamic>;

  Future<DriverApplication> saveProfile(Map<String, dynamic> fields) async =>
      DriverApplication.fromJson(
        await _authorized('PUT', '/driver/profile', body: fields),
      );

  Future<DriverApplication> uploadDriverDocument(
    String type,
    List<int> bytes, {
    String? licenseCategory,
    String contentType = 'image/jpeg',
  }) async {
    final path = '/driver/documents/$type';
    return DriverApplication.fromJson(
      await _authorized(
        'PUT',
        path,
        bytes: bytes,
        contentType: contentType,
        query: licenseCategory == null
            ? null
            : {'licenseCategory': licenseCategory},
      ),
    );
  }

  Future<DriverApplication> saveVehicle(
    Map<String, dynamic> fields, {
    String? vehicleId,
  }) async => DriverApplication.fromJson(
    await _authorized(
      vehicleId == null ? 'POST' : 'PATCH',
      vehicleId == null ? '/driver/vehicles' : '/driver/vehicles/$vehicleId',
      body: fields,
    ),
  );

  Future<DriverApplication> uploadVehicleDocument(
    String vehicleId,
    String type,
    List<int> bytes, {
    String contentType = 'image/jpeg',
  }) async => DriverApplication.fromJson(
    await _authorized(
      'PUT',
      '/driver/vehicles/$vehicleId/documents/$type',
      bytes: bytes,
      contentType: contentType,
    ),
  );

  Future<Map<String, dynamic>> savePayoutAccount(Map<String, dynamic> fields) =>
      _authorized('PUT', '/me/payout-account', body: fields);

  Future<DriverApplication> submitApplication() async =>
      DriverApplication.fromJson(
        await _authorized(
          'POST',
          '/driver/application/submit',
          body: {'confirm': true},
        ),
      );

  Future<Map<String, dynamic>> _publicRequest(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final request = http.Request(method, _uri(path));
    request.headers['Content-Type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);
    return _send(request);
  }

  Future<Map<String, dynamic>> _authorized(
    String method,
    String path, {
    Map<String, dynamic>? body,
    List<int>? bytes,
    String? contentType,
    Map<String, String>? query,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString(_accessTokenKey);
    if (token == null) {
      throw const DriverApiException(
        'UNAUTHENTICATED',
        'سجّل الدخول للمتابعة.',
      );
    }
    var response = await _sendAuthorized(
      method,
      path,
      token,
      body: body,
      bytes: bytes,
      contentType: contentType,
      query: query,
    );
    if (response.statusCode == 401 &&
        _errorCode(response.body) == 'TOKEN_EXPIRED') {
      token = await _refreshToken(prefs);
      response = await _sendAuthorized(
        method,
        path,
        token,
        body: body,
        bytes: bytes,
        contentType: contentType,
        query: query,
      );
    }
    try {
      return _decode(response);
    } on DriverApiException catch (error) {
      if (error.requiresLogin) await clearTokens();
      rethrow;
    }
  }

  Future<http.Response> _sendAuthorized(
    String method,
    String path,
    String token, {
    Map<String, dynamic>? body,
    List<int>? bytes,
    String? contentType,
    Map<String, String>? query,
  }) async {
    final request = http.Request(method, _uri(path, query));
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Content-Type'] = contentType ?? 'application/json';
    if (bytes != null) {
      request.bodyBytes = bytes;
    } else if (body != null) {
      request.body = jsonEncode(body);
    }
    final streamedResponse = await _client
        .send(request)
        .timeout(const Duration(seconds: 90));
    return http.Response.fromStream(
      streamedResponse,
    ).timeout(const Duration(seconds: 90));
  }

  Future<String> _refreshToken(SharedPreferences prefs) async {
    final refreshToken = prefs.getString(_refreshTokenKey);
    if (refreshToken == null) {
      await clearTokens();
      throw const DriverApiException(
        'SESSION_ENDED',
        'انتهت الجلسة، سجّل الدخول مجددًا.',
      );
    }
    try {
      final response = await _publicRequest('POST', '/auth/refresh', {
        'refreshToken': refreshToken,
      });
      await saveTokens(response);
      return response['accessToken'] as String;
    } on DriverApiException catch (error) {
      if (error.requiresLogin) await clearTokens();
      rethrow;
    }
  }

  Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final basePath = _baseUri.path.replaceFirst(RegExp(r'/+$'), '');
    final relativePath = path.startsWith('/') ? path : '/$path';
    return _baseUri.replace(
      path: '$basePath$relativePath',
      queryParameters: query,
    );
  }

  List<Map<String, dynamic>> _mapList(Object? value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();

  Future<Map<String, dynamic>> _send(http.Request request) async {
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 90));
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final data = response.body.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(response.body) as Map).cast<String, dynamic>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error =
          (data['error'] as Map?)?.cast<String, dynamic>() ?? const {};
      final code = error['code'] as String? ?? 'REQUEST_FAILED';
      throw DriverApiException(
        code,
        _userMessage(code),
        field: error['field'] as String?,
        missing: (error['missing'] as List?)?.map((e) => e.toString()).toList(),
      );
    }
    return data;
  }

  String? _errorCode(String body) {
    try {
      final data = jsonDecode(body) as Map;
      return (data['error'] as Map?)?['code'] as String?;
    } on FormatException {
      return null;
    }
  }

  String _userMessage(String code) => switch (code) {
    'NOT_LOGGED_IN' ||
    'INVALID_TOKEN' ||
    'SESSION_ENDED' ||
    'UNAUTHENTICATED' => 'انتهت الجلسة. سجّل الدخول مرة أخرى.',
    'TOKEN_EXPIRED' => 'انتهت صلاحية الجلسة. حاول مرة أخرى.',
    'ACCOUNT_SUSPENDED' => 'الحساب موقوف. تواصل مع الدعم.',
    'ROLE_REQUIRED' => 'هذا الحساب غير مسجل كسائق.',
    'WRONG_EMAIL_OR_PASSWORD' => 'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
    'EMAIL_NOT_VERIFIED' => 'أكد بريدك الإلكتروني باستخدام الرمز المرسل إليك.',
    'EMAIL_TAKEN' => 'البريد الإلكتروني مسجل بالفعل.',
    'WRONG_CODE' => 'الرمز غير صحيح. راجعه وحاول مرة أخرى.',
    'CODE_EXPIRED' => 'انتهت صلاحية الرمز. اطلب رمزًا جديدًا.',
    'CODE_LOCKED' => 'تم قفل الرمز. تواصل مع الدعم للحصول على رمز جديد.',
    'OFFER_EXPIRED' => 'انتهت مهلة الطلب.',
    'OFFER_GONE' => 'لم يعد هذا الطلب متاحًا.',
    'SCHEDULE_CONFLICT' => 'يتعارض موعد الطلب مع رحلة أخرى.',
    'NOT_ONLINE' => 'أنت غير متصل الآن. ارجع إلى الشاشة الرئيسية.',
    'NOT_APPROVED' => 'لم تتم الموافقة على حساب السائق بعد.',
    'POLICIES_NOT_ACCEPTED' => 'اقبل أحدث الشروط للمتابعة.',
    'DEBT_OVER_LIMIT' => 'تجاوز رصيدك الحد المسموح به.',
    'WRONG_STEP' => 'حالة الرحلة تغيرت. حدّث الشاشة وحاول مرة أخرى.',
    'PHOTO_REQUIRED' => 'ارفع صورة واحدة على الأقل للمتابعة.',
    'CASH_NOT_COLLECTED' => 'أكد تحصيل المبلغ النقدي قبل المتابعة.',
    'CODE_NOT_VERIFIED' => 'تحقق من رمز التسليم قبل إكمال الرحلة.',
    'APPLICATION_INCOMPLETE' => 'أكمل البيانات والمستندات الناقصة.',
    'APPLICATION_LOCKED' => 'لا يمكن تعديل الطلب في حالته الحالية.',
    'TOO_LARGE' => 'حجم الصورة أكبر من 5 ميجابايت.',
    'INVALID_IMAGE' || 'UNSUPPORTED_IMAGE' =>
      'صيغة الصورة غير مدعومة. استخدم JPEG أو PNG أو WEBP.',
    'TOO_MANY_REQUESTS' => 'محاولات كثيرة. انتظر قليلًا ثم حاول مجددًا.',
    'TOO_MANY_ATTEMPTS' => 'محاولات كثيرة. اطلب رمزًا جديدًا.',
    _ => 'تعذر إكمال الطلب. راجع البيانات وحاول مرة أخرى.',
  };

  void close() => _client.close();
}
