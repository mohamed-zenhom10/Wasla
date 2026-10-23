class CargoOrderDraft {
  String category = '';
  String description = '';
  String pickup = '';
  String destination = '';
  String size = 'Medium';
  String notes = '';
  bool hasSamplePhoto = false;
  final List<String> stops = [];
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

  static final List<CargoActivityItem> _activity = [
    const CargoActivityItem(
      reference: 'W-2408',
      title: 'Furniture delivery',
      route: 'Nasr City  →  Maadi',
      status: 'Completed',
      dateLabel: 'Yesterday',
    ),
    const CargoActivityItem(
      reference: 'W-2403',
      title: 'Household appliances',
      route: 'Heliopolis  →  New Cairo',
      status: 'In transit',
      dateLabel: 'Oct 18',
    ),
  ];

  static List<CargoActivityItem> get activity => List.unmodifiable(_activity);

  static CargoActivityItem saveDemoOrder(CargoOrderDraft draft) {
    final route = <String>[
      draft.pickup,
      ...draft.stops,
      draft.destination,
    ].join('  →  ');
    final order = CargoActivityItem(
      reference: 'W-${2500 + _activity.length}',
      title: draft.description.trim().isEmpty
          ? draft.category
          : draft.description.trim(),
      route: route,
      status: 'Demo request saved',
      dateLabel: 'Just now',
    );
    _activity.insert(0, order);
    return order;
  }
}
