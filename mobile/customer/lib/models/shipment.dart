class ShipmentLocation {
  const ShipmentLocation({
    required this.address,
    required this.latitude,
    required this.longitude,
    this.notes,
    this.zoneId,
  });

  final String address;
  final double latitude;
  final double longitude;
  final String? notes;
  final String? zoneId;

  Map<String, dynamic> toJson() => {
    'address': address,
    'lat': latitude,
    'lng': longitude,
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
  };

  factory ShipmentLocation.fromJson(Map<String, dynamic> json) =>
      ShipmentLocation(
        address: json['address']?.toString() ?? '',
        latitude: (json['lat'] as num?)?.toDouble() ?? 0,
        longitude: (json['lng'] as num?)?.toDouble() ?? 0,
        notes: json['notes']?.toString(),
        zoneId: json['zoneId']?.toString(),
      );
}

class ShipmentPhoto {
  const ShipmentPhoto({required this.id, required this.url, this.uploadedAt});

  final String id;
  final String url;
  final DateTime? uploadedAt;

  factory ShipmentPhoto.fromJson(Map<String, dynamic> json) => ShipmentPhoto(
    id: json['id']?.toString() ?? '',
    url: json['url']?.toString() ?? '',
    uploadedAt: DateTime.tryParse(json['uploadedAt']?.toString() ?? ''),
  );
}

class ShipmentQuote {
  const ShipmentQuote({
    required this.id,
    required this.vehicleTypeId,
    required this.status,
    required this.recommended,
    required this.customerAmount,
    required this.helpersCount,
    required this.helpersAmount,
    required this.expiresAt,
    this.transportAmount,
    this.helperFee,
    this.returnDiscountAmount,
    this.groupDiscountAmount,
    this.couponDiscountAmount,
    this.amount,
    this.pricingSource,
    this.pricingDetails,
    this.acceptedAt,
  });

  final String id;
  final String vehicleTypeId;
  final String status;
  final bool recommended;
  final String customerAmount;
  final int helpersCount;
  final String helpersAmount;
  final DateTime? expiresAt;
  final String? transportAmount;
  final String? helperFee;
  final String? returnDiscountAmount;
  final String? groupDiscountAmount;
  final String? couponDiscountAmount;
  final String? amount;
  final String? pricingSource;
  final Map<String, dynamic>? pricingDetails;
  final DateTime? acceptedAt;

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());

  factory ShipmentQuote.fromJson(Map<String, dynamic> json) => ShipmentQuote(
    id: json['id']?.toString() ?? '',
    vehicleTypeId: json['vehicleTypeId']?.toString() ?? '',
    status: json['status']?.toString() ?? '',
    recommended: json['recommended'] == true,
    customerAmount: json['customerAmount']?.toString() ?? '',
    helpersCount: (json['helpersCount'] as num?)?.toInt() ?? 0,
    helpersAmount: json['helpersAmount']?.toString() ?? '0.00',
    expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
    transportAmount: json['transportAmount']?.toString(),
    helperFee: json['helperFee']?.toString(),
    returnDiscountAmount: json['returnDiscountAmount']?.toString(),
    groupDiscountAmount: json['groupDiscountAmount']?.toString(),
    couponDiscountAmount: json['couponDiscountAmount']?.toString(),
    amount: json['amount']?.toString(),
    pricingSource: json['pricingSource']?.toString(),
    pricingDetails: json['pricingDetails'] is Map
        ? Map<String, dynamic>.from(json['pricingDetails'] as Map)
        : null,
    acceptedAt: DateTime.tryParse(json['acceptedAt']?.toString() ?? ''),
  );
}

class ShipmentTimelineEntry {
  const ShipmentTimelineEntry({
    this.from,
    required this.to,
    required this.by,
    this.reason,
    this.at,
  });

  final String? from;
  final String to;
  final String by;
  final String? reason;
  final DateTime? at;

  factory ShipmentTimelineEntry.fromJson(Map<String, dynamic> json) =>
      ShipmentTimelineEntry(
        from: json['from']?.toString(),
        to: json['to']?.toString() ?? '',
        by: json['by']?.toString() ?? '',
        reason: json['reason']?.toString(),
        at: DateTime.tryParse(json['at']?.toString() ?? ''),
      );
}

class Shipment {
  const Shipment({
    required this.id,
    required this.status,
    this.cargoCategoryId,
    this.sizeOptionId,
    this.cargoDescription,
    this.itemCount,
    this.isFragile,
    this.weightKg,
    this.helpersCount,
    this.requestedVehicleTypeId,
    this.pickup,
    this.dropoff,
    this.pickupType,
    this.pickupAt,
    this.pickupWindowStart,
    this.pickupWindowEnd,
    this.paymentMethod,
    this.farePaidBy,
    this.recipientName,
    this.recipientPhone,
    this.routeDistanceM,
    this.routeDurationS,
    this.deliveryCode,
    this.createdAt,
    this.photos = const [],
    this.quotes = const [],
    this.acceptedQuote,
    this.timeline = const [],
  });

  final String id;
  final String status;
  final String? cargoCategoryId;
  final String? sizeOptionId;
  final String? cargoDescription;
  final int? itemCount;
  final bool? isFragile;
  final double? weightKg;
  final int? helpersCount;
  final String? requestedVehicleTypeId;
  final ShipmentLocation? pickup;
  final ShipmentLocation? dropoff;
  final String? pickupType;
  final DateTime? pickupAt;
  final DateTime? pickupWindowStart;
  final DateTime? pickupWindowEnd;
  final String? paymentMethod;
  final String? farePaidBy;
  final String? recipientName;
  final String? recipientPhone;
  final int? routeDistanceM;
  final int? routeDurationS;
  final String? deliveryCode;
  final DateTime? createdAt;
  final List<ShipmentPhoto> photos;
  final List<ShipmentQuote> quotes;
  final ShipmentQuote? acceptedQuote;
  final List<ShipmentTimelineEntry> timeline;

  bool get isEditable => status == 'draft' && acceptedQuote == null;

  factory Shipment.fromResponse(Map<String, dynamic> response) {
    final raw = response['shipment'];
    if (raw is! Map) {
      throw const FormatException(
        'Shipment response is missing shipment data.',
      );
    }
    return Shipment.fromJson(Map<String, dynamic>.from(raw));
  }

  factory Shipment.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? parseMap(Object? value) =>
        value is Map ? Map<String, dynamic>.from(value) : null;
    List<T> parseList<T>(
      Object? value,
      T Function(Map<String, dynamic>) parser,
    ) => value is List
        ? value
              .whereType<Map>()
              .map((item) => parser(Map<String, dynamic>.from(item)))
              .toList()
        : <T>[];

    return Shipment(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'draft',
      cargoCategoryId: json['cargoCategoryId']?.toString(),
      sizeOptionId: json['sizeOptionId']?.toString(),
      cargoDescription: json['cargoDescription']?.toString(),
      itemCount: (json['itemCount'] as num?)?.toInt(),
      isFragile: json['isFragile'] as bool?,
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      helpersCount: (json['helpersCount'] as num?)?.toInt(),
      requestedVehicleTypeId: json['requestedVehicleTypeId']?.toString(),
      pickup: parseMap(json['pickup']) == null
          ? null
          : ShipmentLocation.fromJson(parseMap(json['pickup'])!),
      dropoff: parseMap(json['dropoff']) == null
          ? null
          : ShipmentLocation.fromJson(parseMap(json['dropoff'])!),
      pickupType: json['pickupType']?.toString(),
      pickupAt: DateTime.tryParse(json['pickupAt']?.toString() ?? ''),
      pickupWindowStart: DateTime.tryParse(
        json['pickupWindowStart']?.toString() ?? '',
      ),
      pickupWindowEnd: DateTime.tryParse(
        json['pickupWindowEnd']?.toString() ?? '',
      ),
      paymentMethod: json['paymentMethod']?.toString(),
      farePaidBy: json['farePaidBy']?.toString(),
      recipientName:
          parseMap(json['recipient'])?['name']?.toString() ??
          json['recipientName']?.toString(),
      recipientPhone:
          parseMap(json['recipient'])?['phone']?.toString() ??
          json['recipientPhone']?.toString(),
      routeDistanceM: (json['routeDistanceM'] as num?)?.toInt(),
      routeDurationS: (json['routeDurationS'] as num?)?.toInt(),
      deliveryCode: json['deliveryCode']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      photos: parseList(json['photos'], ShipmentPhoto.fromJson),
      quotes: parseList(json['quotes'], ShipmentQuote.fromJson),
      acceptedQuote: parseMap(json['acceptedQuote']) == null
          ? null
          : ShipmentQuote.fromJson(parseMap(json['acceptedQuote'])!),
      timeline: parseList(json['timeline'], ShipmentTimelineEntry.fromJson),
    );
  }
}

class ShipmentListItem {
  const ShipmentListItem({
    required this.id,
    required this.status,
    this.pickupAddress,
    this.dropoffAddress,
    this.pickupWindowStart,
    this.vehicleTypeId,
    this.customerAmount,
  });

  final String id;
  final String status;
  final String? pickupAddress;
  final String? dropoffAddress;
  final DateTime? pickupWindowStart;
  final String? vehicleTypeId;
  final String? customerAmount;

  factory ShipmentListItem.fromJson(Map<String, dynamic> json) =>
      ShipmentListItem(
        id: json['id']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        pickupAddress: _nestedAddress(json['pickup'], json['pickupAddress']),
        dropoffAddress: _nestedAddress(json['dropoff'], json['dropoffAddress']),
        pickupWindowStart: DateTime.tryParse(
          (json['pickupWindowStart'] ?? json['pickupAt'])?.toString() ?? '',
        ),
        vehicleTypeId: json['vehicleTypeId']?.toString(),
        customerAmount: json['customerAmount']?.toString(),
      );

  static String? _nestedAddress(Object? nested, Object? direct) {
    if (direct is String) return direct;
    if (nested is Map) return nested['address']?.toString();
    return null;
  }
}

class ShipmentPage {
  const ShipmentPage({
    required this.shipments,
    required this.page,
    required this.hasMore,
  });

  final List<ShipmentListItem> shipments;
  final int page;
  final bool hasMore;

  factory ShipmentPage.fromJson(Map<String, dynamic> json) => ShipmentPage(
    shipments: (json['shipments'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => ShipmentListItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(),
    page: (json['page'] as num?)?.toInt() ?? 1,
    hasMore: json['hasMore'] == true,
  );
}

class ShipmentSizeOption {
  const ShipmentSizeOption({
    required this.id,
    required this.categoryId,
    required this.nameEn,
    this.nameAr,
    this.code,
    this.approxVolumeM3,
  });

  final String id;
  final String categoryId;
  final String nameEn;
  final String? nameAr;
  final String? code;
  final double? approxVolumeM3;

  factory ShipmentSizeOption.fromJson(Map<String, dynamic> json) =>
      ShipmentSizeOption(
        id: json['id']?.toString() ?? '',
        categoryId: json['categoryId']?.toString() ?? '',
        nameEn: json['nameEn']?.toString() ?? '',
        nameAr: json['nameAr']?.toString(),
        code: json['code']?.toString(),
        approxVolumeM3: (json['approxVolumeM3'] as num?)?.toDouble(),
      );
}

class ShipmentCargoCategory {
  const ShipmentCargoCategory({
    required this.id,
    required this.nameEn,
    this.nameAr,
    this.code,
    this.sizes = const [],
  });

  final String id;
  final String nameEn;
  final String? nameAr;
  final String? code;
  final List<ShipmentSizeOption> sizes;

  factory ShipmentCargoCategory.fromJson(Map<String, dynamic> json) =>
      ShipmentCargoCategory(
        id: json['id']?.toString() ?? '',
        nameEn: json['nameEn']?.toString() ?? '',
        nameAr: json['nameAr']?.toString(),
        code: json['code']?.toString(),
        sizes: (json['sizes'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  ShipmentSizeOption.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(),
      );
}

class ShipmentVehicleType {
  const ShipmentVehicleType({
    required this.id,
    required this.nameEn,
    this.nameAr,
    this.code,
    this.imageUrl,
  });

  final String id;
  final String nameEn;
  final String? nameAr;
  final String? code;
  final String? imageUrl;

  factory ShipmentVehicleType.fromJson(Map<String, dynamic> json) =>
      ShipmentVehicleType(
        id: json['id']?.toString() ?? '',
        nameEn: json['nameEn']?.toString() ?? '',
        nameAr: json['nameAr']?.toString(),
        code: json['code']?.toString(),
        imageUrl: json['imageUrl']?.toString(),
      );
}

class ShipmentCatalog {
  const ShipmentCatalog({
    required this.categories,
    required this.vehicleTypes,
    required this.minScheduleLeadMinutes,
  });

  final List<ShipmentCargoCategory> categories;
  final List<ShipmentVehicleType> vehicleTypes;
  final int minScheduleLeadMinutes;

  factory ShipmentCatalog.fromJson(Map<String, dynamic> json) {
    final settings = json['settings'];
    return ShipmentCatalog(
      categories: (json['cargoCategories'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                ShipmentCargoCategory.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      vehicleTypes: (json['vehicleTypes'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                ShipmentVehicleType.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      minScheduleLeadMinutes: settings is Map
          ? (settings['minScheduleLeadMinutes'] as num?)?.toInt() ?? 30
          : 30,
    );
  }
}
