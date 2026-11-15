import 'package:geolocator/geolocator.dart';

class DriverLocation {
  static Future<Map<String, dynamic>> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('فعّل خدمة الموقع على جهازك وحاول مرة أخرى.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw StateError('اسمح للتطبيق بالوصول إلى موقعك للاتصال بالطلبات.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError('فعّل إذن الموقع للتطبيق من إعدادات الجهاز.');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return {
      'lat': position.latitude,
      'lng': position.longitude,
      'accuracyM': position.accuracy,
    };
  }
}
