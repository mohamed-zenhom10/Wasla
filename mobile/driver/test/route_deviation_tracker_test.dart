import 'package:driver/data/route_deviation_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RouteDeviationTracker', () {
    final start = DateTime(2026, 11, 21, 12);

    test('prompts only after two continuous minutes off route', () {
      final tracker = RouteDeviationTracker();
      expect(
        tracker.update(distanceMeters: 100, accuracyMeters: 5, now: start),
        isFalse,
      );
      expect(tracker.isOffRoute, isTrue);
      expect(
        tracker.update(
          distanceMeters: 100,
          accuracyMeters: 5,
          now: start.add(const Duration(minutes: 1, seconds: 59)),
        ),
        isFalse,
      );
      expect(
        tracker.update(
          distanceMeters: 100,
          accuracyMeters: 5,
          now: start.add(const Duration(minutes: 2)),
        ),
        isTrue,
      );
    });

    test('resets the timer when GPS returns to the route', () {
      final tracker = RouteDeviationTracker();
      tracker.update(distanceMeters: 100, accuracyMeters: 5, now: start);
      expect(
        tracker.update(
          distanceMeters: 20,
          accuracyMeters: 5,
          now: start.add(const Duration(minutes: 1)),
        ),
        isFalse,
      );
      expect(tracker.isOffRoute, isFalse);
      expect(
        tracker.update(
          distanceMeters: 100,
          accuracyMeters: 5,
          now: start.add(const Duration(minutes: 1, seconds: 1)),
        ),
        isFalse,
      );
      expect(
        tracker.update(
          distanceMeters: 100,
          accuracyMeters: 5,
          now: start.add(const Duration(minutes: 3)),
        ),
        isFalse,
      );
    });

    test('accounts for GPS accuracy when deciding whether off route', () {
      final tracker = RouteDeviationTracker();
      expect(
        tracker.update(distanceMeters: 150, accuracyMeters: 80, now: start),
        isFalse,
      );
      expect(tracker.isOffRoute, isFalse);
    });
  });
}
