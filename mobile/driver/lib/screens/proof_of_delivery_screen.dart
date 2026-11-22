import 'package:driver/components/driver_components.dart';
import 'package:driver/components/driver_session.dart';
import 'package:driver/components/driver_navigation_map.dart';
import 'package:driver/data/driver_api.dart';
import 'package:driver/data/driver_trip_location_reporter.dart';
import 'package:driver/screens/delivery_success_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class ProofOfDeliveryScreen extends StatefulWidget {
  const ProofOfDeliveryScreen({super.key, required this.trip, this.api});

  final Map<String, dynamic> trip;
  final DriverApi? api;

  @override
  State<ProofOfDeliveryScreen> createState() => _ProofOfDeliveryScreenState();
}

class _ProofOfDeliveryScreenState extends State<ProofOfDeliveryScreen> {
  late final DriverApi _api = widget.api ?? DriverApi();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _codeController = TextEditingController();
  late Map<String, dynamic> _trip = widget.trip;
  late final DriverTripLocationReporter _locationReporter =
      DriverTripLocationReporter(_api, (error) {
        if (!mounted || handleDriverSessionError(context, error)) return;
        setState(() => _error = _message(error));
      });
  bool _busy = false;
  bool _codeVerified = false;
  String _payment = 'collected';
  String? _error;

  String get _tripId => _trip['id']?.toString() ?? '';
  List<Map<String, dynamic>> get _deliveryPhotos =>
      (((_trip['photos'] as Map?)?['delivery']) as List? ?? const [])
          .whereType<Map>()
          .map((photo) => photo.cast<String, dynamic>())
          .toList();
  bool get _recipientPaysCash =>
      _trip['paymentMethod'] == 'cash' && _trip['farePaidBy'] == 'recipient';
  bool get _atDropoff => _trip['status'] == 'arrived_at_dropoff';
  bool get _verified => _codeVerified || _trip['deliveryCodeVerified'] == true;
  bool get _canComplete =>
      _atDropoff && _verified && _deliveryPhotos.isNotEmpty && !_busy;

  @override
  void initState() {
    super.initState();
    _codeVerified = widget.trip['deliveryCodeVerified'] == true;
    _locationReporter.start();
  }

  @override
  void dispose() {
    _locationReporter.dispose();
    _codeController.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _arriveAtDropoff() async {
    await _run(() async {
      _trip = await _api.updateTrip(_tripId, 'arrive-dropoff');
    });
  }

  Future<void> _verifyCode() async {
    final code = _normalizeDigits(_codeController.text.trim());
    if (!RegExp(r'^\d{4}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 4-digit code from the recipient.');
      return;
    }
    await _run(() async {
      _trip = await _api.updateTrip(
        _tripId,
        'verify-code',
        body: {'code': code},
      );
      _codeVerified = true;
    });
  }

  Future<void> _addDeliveryPhoto() async {
    if (_deliveryPhotos.length >= 6) {
      setState(() => _error = 'You can upload up to 6 delivery photos.');
      return;
    }
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
      );
      if (photo == null || !mounted) return;
      final bytes = await photo.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        throw StateError('حجم الصورة أكبر من 5 ميجابايت. اختر صورة أصغر.');
      }
      await _run(() async {
        _trip = await _api.uploadTripPhoto(
          _tripId,
          'delivery',
          bytes,
          contentType: _contentType(photo.name),
        );
      });
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'Camera error.');
    } catch (error) {
      if (!mounted) return;
      if (handleDriverSessionError(context, error)) return;
      setState(() => _error = _message(error));
    }
  }

  String _contentType(String filename) =>
      switch (filename.split('.').last.toLowerCase()) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => throw StateError('الصورة لازم تكون JPEG أو PNG أو WEBP.'),
      };

  String _normalizeDigits(String value) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    return value.split('').map((digit) {
      final arabicIndex = arabic.indexOf(digit);
      if (arabicIndex >= 0) return '$arabicIndex';
      final persianIndex = persian.indexOf(digit);
      if (persianIndex >= 0) return '$persianIndex';
      return digit;
    }).join();
  }

  Future<void> _completeDelivery() async {
    if (!_canComplete) return;
    await _run(() async {
      _trip = await _api.updateTrip(
        _tripId,
        'deliver',
        body: _recipientPaysCash ? {'payment': _payment} : const {},
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 350),
          pageBuilder: (context, animation, secondaryAnimation) =>
              const DeliverySuccessScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted || handleDriverSessionError(context, error)) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) => error is DriverApiException
      ? error.message
      : error is StateError
      ? error.message
      : 'تعذر تحديث حالة الرحلة. حاول مرة أخرى.';

  @override
  Widget build(BuildContext context) {
    final dropoff = (_trip['dropoff'] as Map?)?['address'] ?? 'Drop-off';
    final recipient =
        (_trip['recipient'] as Map?)?.cast<String, dynamic>() ?? const {};
    final pickupPlace = MapPlace.fromJson(_trip['pickup'], 'Pickup');
    final dropoffPlace = MapPlace.fromJson(_trip['dropoff'], 'Delivery');
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DriverPageHeader(
                      label: 'Confirm a safe delivery',
                      progress: 'Trip $_tripId',
                    ),
                    const Text(
                      'Confirm a safe delivery',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: DriverNavigationMap(
                        height: 360,
                        trackCurrentLocation: true,
                        showNavigationPanel: true,
                        stageLabel: 'Stage 2 · delivery',
                        routeRequired: !_atDropoff,
                        destination: _atDropoff ? null : dropoffPlace,
                        pickup: pickupPlace,
                        dropoff: dropoffPlace,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('Drop-off · $dropoff'),
                    if (recipient.isNotEmpty)
                      Text(
                        'Recipient · ${recipient['name'] ?? '—'} · '
                        '${recipient['phone'] ?? '—'}',
                      ),
                    const SizedBox(height: 16),
                    if (!_atDropoff)
                      PrimaryButton(
                        label: _busy ? 'Updating trip...' : "I've arrived",
                        onPressed: _busy ? null : _arriveAtDropoff,
                      )
                    else ...[
                      const Text(
                        'Recipient delivery code',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9٠-٩۰-۹]'),
                          ),
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: const InputDecoration(
                          hintText: '4-digit code',
                          filled: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _busy || _verified ? null : _verifyCode,
                        child: Text(
                          _verified ? 'Code verified' : 'Verify code',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Delivery photos · ${_deliveryPhotos.length}/6',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _busy ? null : _addDeliveryPhoto,
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('Add photo'),
                          ),
                        ],
                      ),
                      if (_deliveryPhotos.isEmpty)
                        const Text(
                          'At least one delivery photo is required.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      if (_recipientPaysCash) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'Recipient cash payment',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final option in const [
                              ('collected', 'Cash received'),
                              ('refused', 'Payment refused'),
                            ])
                              ChoiceChip(
                                label: Text(option.$2),
                                selected: _payment == option.$1,
                                onSelected: _busy
                                    ? null
                                    : (selected) {
                                        if (selected) {
                                          setState(() => _payment = option.$1);
                                        }
                                      },
                              ),
                          ],
                        ),
                      ],
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: PrimaryButton(
                label: _busy ? 'Saving delivery...' : 'Complete delivery',
                onPressed: _canComplete ? _completeDelivery : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
