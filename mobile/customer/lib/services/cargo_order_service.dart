import 'dart:typed_data';

import 'package:main/models/shipment.dart';

class CargoPhotoDraft {
  const CargoPhotoDraft({
    required this.bytes,
    required this.contentType,
    required this.fileName,
  });

  final Uint8List bytes;
  final String contentType;
  final String fileName;
}

class CargoOrderDraft {
  // Core booking flow fields aligned with Shipment model
  String category = '';
  String? categoryId;
  String? sizeOptionId;
  // Fix: Use cargoDescription to match Shipment model field name
  String cargoDescription = '';
  String pickupAddress = '';
  String dropoffAddress = '';
  double? pickupLatitude;
  double? pickupLongitude;
  double? dropoffLatitude;
  double? dropoffLongitude;
  String pickupNotes = '';
  String dropoffNotes = '';
  String size = 'Medium';
  // Remove cargo notes field (requirement #7)
  int itemCount = 1;
  bool isFragile = false;
  double? weightKg;
  int helpersCount = 0;
  String pickupType = 'now';
  String? requestedVehicleTypeId;
  DateTime? scheduledAt;
  String? paymentMethod = 'cash';
  String farePaidBy = 'sender';
  String recipientName = '';
  String recipientPhone = '';
  bool? backhaulAccepted;
  bool useAiEstimate = false;
  ShipmentCatalog? catalog;
  Shipment? shipment;
  ShipmentQuote? selectedQuote;
  final List<CargoPhotoDraft> photos = [];
  final Map<String, String> fieldErrors = {};
  final List<String> stops = [];

  // Helper method to access cargoDescription for compatibility
  String get description => cargoDescription;
  set description(String value) => cargoDescription = value;

  // Compatibility aliases for fields renamed to align with Shipment model.
  String get pickup => pickupAddress;
  set pickup(String value) => pickupAddress = value;

  String get destination => dropoffAddress;
  set destination(String value) => dropoffAddress = value;

  String? get vehicleId => requestedVehicleTypeId;
  set vehicleId(String? value) => requestedVehicleTypeId = value;

  bool get hasSamplePhoto => photos.isNotEmpty;
}

class CargoActivityItem {
  const CargoActivityItem({
    required this.reference,
    required this.title,
    required this.route,
    required this.status,
    required this.dateLabel,
    this.isDemo = true,
  });

  final String reference;
  final String title;
  final String route;
  final String status;
  final String dateLabel;
  final bool isDemo;
}

class CargoOrderService {
  CargoOrderService._();

  static final List<CargoActivityItem> _activity = [];

  static List<CargoActivityItem> get activity => List.unmodifiable(_activity);
}
