import 'dart:async';

import 'package:driver/data/driver_api.dart';
import 'package:driver/data/driver_location.dart';

class DriverTripLocationReporter {
  DriverTripLocationReporter(this._api, this._onError);

  final DriverApi _api;
  final void Function(Object error) _onError;
  Timer? _timer;
  bool _sending = false;

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 10), (_) => _send());
  }

  Future<void> _send() async {
    if (_sending) return;
    _sending = true;
    try {
      await _api.sendLocation(await DriverLocation.current());
    } catch (error) {
      _onError(error);
      if (error is DriverApiException &&
          (error.code == 'NOT_ONLINE' || error.requiresLogin)) {
        dispose();
      }
    } finally {
      _sending = false;
    }
  }

  void dispose() => _timer?.cancel();
}
