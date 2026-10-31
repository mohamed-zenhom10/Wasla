/// Mock data for AI estimation, vehicle selection, scheduling, and booking review.
/// Kept separate from UI widgets so it can be replaced with real API data later.

class AiEstimateMock {
  const AiEstimateMock._();

  static const estimatedVolume = '4–5 m³';
  static const estimatedWeight = '800–1,000 kg';
  static const recommendedVehicle = 'Quarter Truck';
  static const recommendedPrice = 'EGP 660';
  static const availableNow = '8–15 min';
  static const pickupAddress = '12 Abbas El Akkad, Nasr City';
  static const dropoffAddress = '18 Road 9, Maadi';
  static const baseFare = 'EGP 280';
  static const distanceFee = 'EGP 240';
  static const tollsFee = 'EGP 140';
  static const estimatedPrice = 'EGP 660';
}

class VehicleOption {
  const VehicleOption({
    required this.id,
    required this.name,
    required this.price,
    required this.capacity,
    required this.dimensions,
    required this.suitableFor,
    this.description = '',
    this.available = '8–15 min',
    this.recommended = false,
  });

  final String id;
  final String name;
  final String price;
  final String capacity;
  final String dimensions;
  final String suitableFor;
  final String description;
  final String available;
  final bool recommended;
}

class VehicleMock {
  const VehicleMock._();

  static const small = VehicleOption(
    id: 'small',
    name: 'Suzuki / Small Pickup',
    price: 'EGP 460',
    capacity: 'Approx. 500 kg · 2 m³',
    dimensions: '1.8 × 1.3 × 1 m',
    suitableFor: 'Packages • Small appliances',
  );

  static const quarter = VehicleOption(
    id: 'quarter',
    name: 'Quarter Truck',
    price: 'EGP 660',
    capacity: 'Approx. 1,000 kg · 5 m³',
    dimensions: '2.4 × 1.6 × 1.4 m',
    suitableFor: 'Furniture • Appliances • Medium cargo',
    recommended: true,
  );

  static const jumbo = VehicleOption(
    id: 'jumbo',
    name: 'Jumbo',
    price: 'EGP 1,120',
    capacity: 'Approx. 3,000 kg · 16 m³',
    dimensions: '4.2 × 2 × 1.9 m',
    suitableFor: 'Shop stock • Large furniture loads',
    available: '15 min',
  );

  static const heavy = VehicleOption(
    id: 'heavy',
    name: 'Heavy Truck',
    price: 'EGP 2,100',
    capacity: 'Approx. 10,000 kg · 35 m³',
    dimensions: '6 × 2.4 × 2.4 m',
    suitableFor: 'Construction • Pallets • Commercial loads',
    available: '25 min',
  );

  static const List<VehicleOption> smallAndQuarter = [small, quarter];
  static const List<VehicleOption> jumboAndHeavy = [jumbo, heavy];
}

class BookingSummaryMock {
  const BookingSummaryMock._();

  static const pickup = '12 Abbas El Akkad, Nasr City';
  static const dropoff = '18 Road 9, Maadi';
  static const category = 'Furniture';
  static const vehicle = 'Quarter Truck';
  static const price = 'EGP 660';
  static const pickupTime = 'Today, 14:00';
  static const estimatedDelivery = 'By 15:10';
}

class SmartBackhaulMock {
  const SmartBackhaulMock._();

  static const offerTitle = 'Smart Backhaul Offer';
  static const offerDescription = 'Your driver can pick up a return load on the way back and you get a discount.';
  static const offerPrice = 'EGP 140 off';
  static const returnLoad = 'Office furniture · Maadi';
  static const returnRoute = 'Cairo → Alexandria';
  static const savings = 'EGP 140';
}

class DriverOption {
  const DriverOption({
    required this.id,
    required this.name,
    required this.vehicle,
    required this.rating,
    required this.price,
    required this.available,
    this.completed = 0,
  });

  final String id;
  final String name;
  final String vehicle;
  final String rating;
  final String price;
  final String available;
  final int completed;
}

class DriverMock {
  const DriverMock._();

  static const ahmed = DriverOption(
    id: 'ahmed',
    name: 'Ahmed Hassan',
    vehicle: 'Quarter Truck',
    rating: '4.9',
    price: 'EGP 660',
    available: '6 min away',
    completed: 342,
  );

  static const mariam = DriverOption(
    id: 'mariam',
    name: 'Mariam Adel',
    vehicle: 'Quarter Truck',
    rating: '4.8',
    price: 'EGP 680',
    available: '9 min away',
    completed: 218,
  );

  static const khaled = DriverOption(
    id: 'khaled',
    name: 'Khaled Nabil',
    vehicle: 'Jumbo',
    rating: '4.7',
    price: 'EGP 1,120',
    available: '12 min away',
    completed: 156,
  );

  static const List<DriverOption> available = [ahmed, mariam, khaled];
}

class TrackingMock {
  const TrackingMock._();

  static const driverName = 'Ahmed Hassan';
  static const driverRating = '4.9 ★';
  static const vehicle = 'Quarter Truck • W-2408';
  static const pickup = '12 Abbas El Akkad, Nasr City';
  static const dropoff = '18 Road 9, Maadi';
  static const progress = 0.65;
  static const eta = '14 min';
  static const stages = [
    ('Pickup confirmed', true),
    ('On the way', true),
    ('Arrived at pickup', false),
    ('In transit', false),
    ('Out for delivery', false),
    ('Delivered', false),
  ];
}

class TripMock {
  const TripMock._();

  static const pickup = '12 Abbas El Akkad, Nasr City';
  static const dropoff = '18 Road 9, Maadi';
  static const reference = 'W-2408';
  static const status = 'In transit';
  static const pickupTime = 'Today, 09:12';
  static const estimatedDelivery = 'By 10:02';
  static const actualDelivery = '';
  static const driverName = 'Ahmed Hassan';
  static const driverRating = '4.9 ★';
  static const vehicle = 'Quarter Truck • W-2408';
  static const route = 'Nasr City → Maadi';
  static const distance = '12.4 km';
  static const duration = '42 min';
  static const price = 'EGP 660';
  static const items = [
    'Two-seat sofa',
    'Coffee table',
    '3 medium boxes',
  ];
  static const stops = <String>[];
}

class ChatMock {
  const ChatMock._();

  static const messages = [
    ChatMessage(
      sender: 'driver',
      text: 'On my way, will be there in 10 minutes.',
      time: '09:25',
    ),
    ChatMessage(
      sender: 'you',
      text: 'Great, see you soon.',
      time: '09:24',
    ),
    ChatMessage(
      sender: 'driver',
      text: 'I have your cargo. Gate is on the left.',
      time: '09:15',
    ),
    ChatMessage(
      sender: 'you',
      text: 'Thanks, the gate is open.',
      time: '09:14',
    ),
  ];
}

class ChatMessage {
  const ChatMessage({
    required this.sender,
    required this.text,
    required this.time,
  });

  final String sender;
  final String text;
  final String time;
}

class RatingMock {
  const RatingMock._();

  static const driverName = 'Ahmed Hassan';
  static const vehicle = 'Quarter Truck';
  static const route = 'Nasr City → Maadi';
  static const date = 'Oct 30, 2026';
  static const price = 'EGP 660';
}