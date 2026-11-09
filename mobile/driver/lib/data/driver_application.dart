class DriverApplication {
  const DriverApplication({
    required this.status,
    required this.profile,
    required this.documents,
    required this.vehicles,
    required this.payoutAccount,
    required this.missing,
    this.id,
    this.submittedAt,
    this.reviewedAt,
    this.rejectionReason,
  });

  final String status;
  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> documents;
  final List<Map<String, dynamic>> vehicles;
  final Map<String, dynamic>? payoutAccount;
  final List<String> missing;
  final String? id;
  final String? submittedAt;
  final String? reviewedAt;
  final String? rejectionReason;

  factory DriverApplication.fromJson(Map<String, dynamic> json) {
    final application =
        (json['application'] as Map?)?.cast<String, dynamic>() ?? json;
    return DriverApplication(
      id: application['id']?.toString(),
      status: application['status'] as String? ?? 'not_started',
      submittedAt: application['submittedAt'] as String?,
      reviewedAt: application['reviewedAt'] as String?,
      rejectionReason: application['rejectionReason'] as String?,
      profile:
          (application['profile'] as Map?)?.cast<String, dynamic>() ?? const {},
      documents: _mapList(application['documents']),
      vehicles: _mapList(application['vehicles']),
      payoutAccount: (application['payoutAccount'] as Map?)
          ?.cast<String, dynamic>(),
      missing: (application['missing'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }

  static List<Map<String, dynamic>> _mapList(Object? value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();

  List<Map<String, dynamic>> get allDocuments => [
    ...documents,
    for (final vehicle in vehicles) ..._mapList(vehicle['documents']),
  ];

  Map<String, dynamic>? document(String type) {
    for (final item in allDocuments) {
      if (item['type'] == type) return item;
    }
    return null;
  }

  Map<String, dynamic>? get activeVehicle {
    final activeId = profile['activeVehicleId']?.toString();
    for (final vehicle in vehicles) {
      if (vehicle['id']?.toString() == activeId) return vehicle;
    }
    return vehicles.isEmpty ? null : vehicles.first;
  }

  int get nextStep {
    if (status == 'not_started') {
      return 0;
    }
    if ([
      'profile_photo',
      'national_id_front',
      'national_id_back',
      'driving_license_front',
      'driving_license_back',
      'vehicle_license_front',
      'vehicle_license_back',
    ].any((type) => document(type) == null)) {
      return 0;
    }
    if (missing.contains('profile') ||
        missing.contains('national_id') ||
        missing.contains('min_age') ||
        missing.contains('active_city') ||
        missing.contains('vehicle') ||
        missing.contains('license_too_low')) {
      return 1;
    }
    if (missing.contains('vehicle_documents') ||
        document('vehicle_photo_front') == null ||
        document('vehicle_photo_side') == null ||
        document('vehicle_photo_rear') == null ||
        document('vehicle_photo_cargo') == null) {
      return 2;
    }
    if (missing.contains('payout_account')) return 3;
    return 4;
  }
}
