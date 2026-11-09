import 'package:driver/data/driver_application.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application steps put all identity documents on the first page', () {
    expect(_application().nextStep, 0);
    expect(
      _application(
        documents: _driverDocuments(),
        vehicles: [_vehicleDocuments()],
        missing: ['vehicle'],
      ).nextStep,
      1,
    );
    expect(
      _application(
        documents: _driverDocuments(),
        vehicles: [_vehicleDocuments()],
        missing: ['vehicle_documents'],
      ).nextStep,
      2,
    );
    expect(
      _application(
        documents: _driverDocuments(),
        vehicles: [_vehicleDocuments(withPhotos: true)],
        missing: ['payout_account'],
      ).nextStep,
      3,
    );
    expect(
      _application(
        documents: _driverDocuments(),
        vehicles: [_vehicleDocuments(withPhotos: true)],
      ).nextStep,
      4,
    );
  });
}

DriverApplication _application({
  List<Map<String, dynamic>> documents = const [],
  List<Map<String, dynamic>> vehicles = const [],
  List<String> missing = const [],
}) => DriverApplication(
  status: 'draft',
  profile: const {},
  documents: documents,
  vehicles: vehicles,
  payoutAccount: null,
  missing: missing,
);

List<Map<String, dynamic>> _driverDocuments() => [
  for (final type in const [
    'profile_photo',
    'national_id_front',
    'national_id_back',
    'driving_license_front',
    'driving_license_back',
  ])
    {'type': type},
];

Map<String, dynamic> _vehicleDocuments({bool withPhotos = false}) => {
  'documents': [
    {'type': 'vehicle_license_front'},
    {'type': 'vehicle_license_back'},
    if (withPhotos) ...[
      {'type': 'vehicle_photo_front'},
      {'type': 'vehicle_photo_side'},
      {'type': 'vehicle_photo_rear'},
      {'type': 'vehicle_photo_cargo'},
    ],
  ],
};
