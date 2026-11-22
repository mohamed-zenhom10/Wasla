import 'dart:math' as math;

class RouteDeviationTracker {
  RouteDeviationTracker({
    this.minimumDistanceMeters = 75,
    this.requiredDuration = const Duration(minutes: 2),
  });

  final double minimumDistanceMeters;
  final Duration requiredDuration;

  DateTime? _offRouteSince;

  bool get isOffRoute => _offRouteSince != null;

  bool update({
    required double distanceMeters,
    required double accuracyMeters,
    required DateTime now,
  }) {
    final accuracyThreshold = accuracyMeters.isFinite
        ? accuracyMeters * 2
        : minimumDistanceMeters;
    final threshold = math.max(minimumDistanceMeters, accuracyThreshold);
    if (!distanceMeters.isFinite || distanceMeters <= threshold) {
      reset();
      return false;
    }

    _offRouteSince ??= now;
    return now.difference(_offRouteSince!) >= requiredDuration;
  }

  Duration timeUntilPrompt(DateTime now) {
    final startedAt = _offRouteSince;
    if (startedAt == null) return requiredDuration;
    final remaining = requiredDuration - now.difference(startedAt);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void reset() {
    _offRouteSince = null;
  }
}
