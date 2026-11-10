import 'dart:math' as math;

import 'package:main/models/shipment.dart';
import 'package:main/services/auth_service.dart';

class ShipmentApiException implements Exception {
  const ShipmentApiException({
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

class ShipmentService {
  Future<ShipmentCatalog> getCatalog() async {
    final response = await _request(
      method: 'GET',
      endpoint: '/catalog',
      authenticated: false,
    );
    return ShipmentCatalog.fromJson(response);
  }

  Future<Shipment> createDraft({
    required ShipmentCatalog catalog,
    required String cargoCategoryId,
    String? sizeOptionId,
    required String cargoDescription,
    required int itemCount,
    bool? isFragile,
    double? weightKg,
    int helpersCount = 0,
    String? requestedVehicleTypeId,
    required ShipmentLocation pickup,
    required ShipmentLocation dropoff,
    required String pickupType,
    DateTime? pickupAt,
    required String paymentMethod,
    String farePaidBy = 'sender',
    String? recipientName,
    String? recipientPhone,
    DateTime? now,
  }) async {
    _validateCreate(
      catalog: catalog,
      cargoCategoryId: cargoCategoryId,
      sizeOptionId: sizeOptionId,
      cargoDescription: cargoDescription,
      itemCount: itemCount,
      helpersCount: helpersCount,
      pickup: pickup,
      dropoff: dropoff,
      pickupType: pickupType,
      pickupAt: pickupAt,
      paymentMethod: paymentMethod,
      farePaidBy: farePaidBy,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      now: now ?? DateTime.now(),
    );

    final body = <String, dynamic>{
      'cargoCategoryId': cargoCategoryId,
      ...?(sizeOptionId == null ? null : {'sizeOptionId': sizeOptionId}),
      'cargoDescription': cargoDescription.trim(),
      'itemCount': itemCount,
      ...?(isFragile == null ? null : {'isFragile': isFragile}),
      ...?(weightKg == null ? null : {'weightKg': weightKg}),
      'helpersCount': helpersCount,
      ...?(requestedVehicleTypeId == null
          ? null
          : {'requestedVehicleTypeId': requestedVehicleTypeId}),
      'pickup': pickup.toJson(),
      'dropoff': dropoff.toJson(),
      'pickupType': pickupType,
      ...?(pickupType == 'scheduled'
          ? {'pickupAt': pickupAt!.toUtc().toIso8601String()}
          : null),
      'paymentMethod': paymentMethod,
      'farePaidBy': farePaidBy,
      if (farePaidBy == 'recipient') ...{
        'recipientName': recipientName!.trim(),
        'recipientPhone': recipientPhone!.trim(),
      },
    };

    return Shipment.fromResponse(
      await _request(method: 'POST', endpoint: '/shipments', body: body),
    );
  }

  Future<Shipment> updateDraft(
    Shipment shipment,
    Map<String, dynamic> changedFields,
  ) async {
    _ensureEditable(shipment);
    if (changedFields.isEmpty) return shipment;
    const allowed = {
      'cargoCategoryId',
      'sizeOptionId',
      'cargoDescription',
      'itemCount',
      'isFragile',
      'weightKg',
      'helpersCount',
      'requestedVehicleTypeId',
      'pickup',
      'dropoff',
      'pickupType',
      'pickupAt',
      'paymentMethod',
      'farePaidBy',
      'recipientName',
      'recipientPhone',
    };
    final payload = <String, dynamic>{};
    for (final entry in changedFields.entries) {
      if (!allowed.contains(entry.key)) {
        throw ShipmentApiException(
          code: 'INVALID_INPUT',
          field: entry.key,
          message: 'This field cannot be updated.',
        );
      }
      payload[entry.key] = entry.value;
    }
    final helpersCount = payload['helpersCount'];
    if (helpersCount is int && (helpersCount < 0 || helpersCount > 20)) {
      throw const ShipmentApiException(
        code: 'INVALID_INPUT',
        field: 'helpersCount',
        message: 'Helpers must be between 0 and 20.',
      );
    }
    final pickupType = payload['pickupType'];
    if (pickupType is String &&
        pickupType != 'now' &&
        pickupType != 'scheduled') {
      _invalid('pickupType', 'Choose now or scheduled pickup.');
    }
    if (pickupType == 'scheduled' &&
        payload['pickupAt'] == null &&
        shipment.pickupAt == null) {
      _invalid('pickupAt', 'Scheduled pickup requires a date and time.');
    }
    return Shipment.fromResponse(
      await _request(
        method: 'PATCH',
        endpoint: '/shipments/${shipment.id}',
        body: payload,
      ),
    );
  }

  Future<Shipment> uploadPhoto({
    required Shipment shipment,
    required List<int> bytes,
    required String contentType,
  }) async {
    _ensureEditable(shipment);
    if (!const {
      'image/jpeg',
      'image/png',
      'image/webp',
    }.contains(contentType.toLowerCase())) {
      throw const ShipmentApiException(
        code: 'UNSUPPORTED_IMAGE',
        field: 'photos',
        message: 'Choose a JPEG, PNG, or WebP image.',
      );
    }
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const ShipmentApiException(
        code: 'TOO_LARGE',
        field: 'photos',
        message: 'Each photo must be smaller than 5 MB.',
      );
    }
    if (shipment.photos.length >= 10) {
      throw const ShipmentApiException(
        code: 'TOO_MANY_PHOTOS',
        field: 'photos',
        message: 'A shipment can have up to 10 photos.',
      );
    }
    return Shipment.fromResponse(
      await _request(
        method: 'PUT',
        endpoint: '/shipments/${shipment.id}/photos',
        bytes: bytes,
        contentType: contentType.toLowerCase(),
      ),
    );
  }

  Future<Shipment> removePhoto({
    required Shipment shipment,
    required String photoId,
  }) async {
    _ensureEditable(shipment);
    final response = await _request(
      method: 'DELETE',
      endpoint: '/shipments/${shipment.id}/photos/$photoId',
    );
    if (response['shipment'] is Map) return Shipment.fromResponse(response);
    return getShipment(shipment.id);
  }

  Future<Shipment> requestQuotes(Shipment shipment) async {
    _ensureEditable(shipment);
    if (shipment.photos.isEmpty) {
      throw const ShipmentApiException(
        code: 'PHOTO_REQUIRED',
        field: 'photos',
        message: 'Upload at least one cargo photo before requesting quotes.',
      );
    }
    return Shipment.fromResponse(
      await _request(
        method: 'POST',
        endpoint: '/shipments/${shipment.id}/quotes',
      ),
    );
  }

  Future<Shipment> acceptQuote({
    required Shipment shipment,
    required ShipmentQuote quote,
  }) async {
    _ensureEditable(shipment);
    if (quote.isExpired) {
      throw const ShipmentApiException(
        code: 'QUOTE_EXPIRED',
        message: 'This quote has expired. Request fresh quotes to continue.',
      );
    }
    return Shipment.fromResponse(
      await _request(
        method: 'POST',
        endpoint: '/shipments/${shipment.id}/quotes/${quote.id}/accept',
      ),
    );
  }

  Future<Shipment> withdrawPrice(Shipment shipment) async {
    if (shipment.acceptedQuote == null) {
      throw const ShipmentApiException(
        code: 'PRICE_NOT_ACCEPTED',
        message: 'There is no accepted price to withdraw.',
      );
    }
    return Shipment.fromResponse(
      await _request(
        method: 'POST',
        endpoint: '/shipments/${shipment.id}/withdraw-price',
      ),
    );
  }

  Future<Shipment> getShipment(String id) async => Shipment.fromResponse(
    await _request(method: 'GET', endpoint: '/shipments/$id'),
  );

  Future<ShipmentPage> getShipments({
    String status = 'active',
    int page = 1,
  }) async {
    const supported = {
      'active',
      'draft',
      'searching_driver',
      'driver_assigned',
      'in_progress',
      'delivered',
      'cancelled',
    };
    if (!supported.contains(status) || page < 1) {
      throw const ShipmentApiException(
        code: 'INVALID_INPUT',
        message: 'Choose a valid shipment filter and page.',
      );
    }
    final response = await _request(
      method: 'GET',
      endpoint: '/shipments',
      query: {'status': status, 'page': '$page'},
    );
    return ShipmentPage.fromJson(response);
  }

  Future<Map<String, dynamic>> _request({
    required String method,
    required String endpoint,
    Map<String, dynamic>? body,
    List<int>? bytes,
    String? contentType,
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    try {
      return await AuthService.apiRequest(
        method: method,
        endpoint: endpoint,
        body: body,
        bytes: bytes,
        contentType: contentType,
        query: query,
        authenticated: authenticated,
      );
    } on AuthenticatedApiException catch (error) {
      throw ShipmentApiException(
        code: error.code,
        message: error.message,
        field: error.field,
        statusCode: error.statusCode,
      );
    }
  }

  void _ensureEditable(Shipment shipment) {
    if (!shipment.isEditable) {
      throw const ShipmentApiException(
        code: 'PRICE_ACCEPTED',
        message: 'Withdraw the accepted price before editing this shipment.',
      );
    }
  }

  void _validateCreate({
    required ShipmentCatalog catalog,
    required String cargoCategoryId,
    required String? sizeOptionId,
    required String cargoDescription,
    required int itemCount,
    required int helpersCount,
    required ShipmentLocation pickup,
    required ShipmentLocation dropoff,
    required String pickupType,
    required DateTime? pickupAt,
    required String paymentMethod,
    required String farePaidBy,
    required String? recipientName,
    required String? recipientPhone,
    required DateTime now,
  }) {
    const categories = {
      'cargoCategoryId': 'Select a cargo category.',
      'cargoDescription': 'Describe the cargo.',
      'itemCount': 'Enter the item count.',
      'pickup': 'Select a pickup location on the map.',
      'dropoff': 'Select a drop-off location on the map.',
      'pickupType': 'Choose when to pick up.',
      'paymentMethod': 'Choose a payment method.',
    };
    if (!catalog.categories.any((item) => item.id == cargoCategoryId)) {
      _invalid('cargoCategoryId', categories['cargoCategoryId']!);
    }
    if (sizeOptionId != null &&
        !catalog.categories
            .firstWhere((item) => item.id == cargoCategoryId)
            .sizes
            .any((size) => size.id == sizeOptionId)) {
      _invalid('sizeOptionId', 'Choose a size from the selected category.');
    }
    if (cargoDescription.trim().isEmpty) {
      _invalid('cargoDescription', categories['cargoDescription']!);
    }
    if (itemCount < 1) {
      _invalid('itemCount', categories['itemCount']!);
    }
    if (helpersCount < 0 || helpersCount > 20) {
      _invalid('helpersCount', 'Helpers must be between 0 and 20.');
    }
    if (pickup.address.trim().isEmpty) {
      _invalid('pickup', categories['pickup']!);
    }
    if (dropoff.address.trim().isEmpty) {
      _invalid('dropoff', categories['dropoff']!);
    }
    if (pickupType != 'now' && pickupType != 'scheduled') {
      _invalid('pickupType', categories['pickupType']!);
    }
    if (pickupType == 'scheduled') {
      if (pickupAt == null) {
        _invalid('pickupAt', 'Choose a pickup date and time.');
      }
      final leadTime = Duration(minutes: catalog.minScheduleLeadMinutes);
      if (pickupAt.isBefore(now.add(leadTime))) {
        _invalid(
          'pickupAt',
          'Choose a pickup time at least ${catalog.minScheduleLeadMinutes} minutes from now.',
          code: 'SCHEDULE_TOO_SOON',
        );
      }
      if (pickupAt.isAfter(now.add(const Duration(days: 30)))) {
        _invalid(
          'pickupAt',
          'Scheduled pickup must be within the next 30 days.',
        );
      }
    }
    if (paymentMethod != 'cash' && paymentMethod != 'wallet') {
      _invalid('paymentMethod', categories['paymentMethod']!);
    }
    if (farePaidBy != 'sender' && farePaidBy != 'recipient') {
      _invalid('farePaidBy', 'Choose who pays the fare.');
    }
    if (farePaidBy == 'recipient') {
      if (paymentMethod != 'cash') {
        _invalid('paymentMethod', 'Recipient-paid fares must use cash.');
      }
      if (recipientName == null || recipientName.trim().isEmpty) {
        _invalid('recipientName', 'Enter the recipient name.');
      }
      if (recipientPhone == null || recipientPhone.trim().isEmpty) {
        _invalid('recipientPhone', 'Enter the recipient phone number.');
      }
    }
    if (_distanceMeters(pickup, dropoff) < 200) {
      _invalid('dropoff', 'Pickup and drop-off must be at least 200 m apart.');
    }
  }

  Never _invalid(
    String field,
    String message, {
    String code = 'INVALID_INPUT',
  }) {
    throw ShipmentApiException(code: code, field: field, message: message);
  }

  double _distanceMeters(ShipmentLocation first, ShipmentLocation second) {
    const earthRadiusMeters = 6371000.0;
    final latitudeDelta = _radians(second.latitude - first.latitude);
    final longitudeDelta = _radians(second.longitude - first.longitude);
    final a =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(_radians(first.latitude)) *
            math.cos(_radians(second.latitude)) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _radians(double value) => value * math.pi / 180;
}
