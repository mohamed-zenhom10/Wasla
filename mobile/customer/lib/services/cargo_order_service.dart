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
  String category = '';
  String? categoryId;
  String? sizeOptionId;
  String description = '';
  String pickup = '';
  String destination = '';
  double? pickupLatitude;
  double? pickupLongitude;
  double? dropoffLatitude;
  double? dropoffLongitude;
  String pickupNotes = '';
  String dropoffNotes = '';
  String size = 'Medium';
  String notes = '';
  int itemCount = 1;
  bool isFragile = false;
  double? weightKg;
  int helpersCount = 0;
  String pickupType = 'now';
  String? vehicleId;
  DateTime? scheduledAt;
  String paymentMethod = 'cash';
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
