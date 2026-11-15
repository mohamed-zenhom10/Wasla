import 'package:driver/components/driver_components.dart';
import 'package:driver/components/driver_session.dart';
import 'package:driver/data/driver_api.dart';
import 'package:driver/data/driver_trip_location_reporter.dart';
import 'package:driver/screens/proof_of_delivery_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class CargoLoadedScreen extends StatefulWidget {
  const CargoLoadedScreen({super.key, required this.trip, this.api});

  final Map<String, dynamic> trip;
  final DriverApi? api;

  @override
  State<CargoLoadedScreen> createState() => _CargoLoadedScreenState();
}

class _CargoLoadedScreenState extends State<CargoLoadedScreen> {
  late final DriverApi _api = widget.api ?? DriverApi();
  final ImagePicker _picker = ImagePicker();
  late Map<String, dynamic> _trip = widget.trip;
  late final DriverTripLocationReporter _locationReporter =
      DriverTripLocationReporter(_api, (error) {
        if (!mounted || handleDriverSessionError(context, error)) return;
        setState(() => _error = _message(error));
      });
  bool _cashCollected = false;
  bool _busy = false;
  String _vehicleFit = 'suitable';
  String? _error;

  String get _tripId => _trip['id']?.toString() ?? '';
  List<Map<String, dynamic>> get _pickupPhotos =>
      (((_trip['photos'] as Map?)?['pickup']) as List? ?? const [])
          .whereType<Map>()
          .map((photo) => photo.cast<String, dynamic>())
          .toList();
  double get _cashToCollect =>
      double.tryParse(_trip['cashToCollect']?.toString() ?? '') ?? 0;
  bool get _collectAtPickup =>
      _trip['paymentMethod'] == 'cash' &&
      _trip['farePaidBy'] == 'sender' &&
      _cashToCollect > 0;
  bool get _canDepart =>
      !_busy &&
      _pickupPhotos.isNotEmpty &&
      (!_collectAtPickup || _cashCollected);

  @override
  void initState() {
    super.initState();
    _locationReporter.start();
  }

  @override
  void dispose() {
    _locationReporter.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _addPickupPhoto() async {
    if (_pickupPhotos.length >= 6) {
      setState(() => _error = 'You can upload up to 6 pickup photos.');
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
      setState(() {
        _busy = true;
        _error = null;
      });
      _trip = await _api.uploadTripPhoto(
        _tripId,
        'pickup',
        bytes,
        contentType: _contentType(photo.name),
      );
      if (mounted) setState(() {});
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'Camera error.');
    } catch (error) {
      if (!mounted || handleDriverSessionError(context, error)) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _contentType(String filename) =>
      switch (filename.split('.').last.toLowerCase()) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => throw StateError('الصورة لازم تكون JPEG أو PNG أو WEBP.'),
      };

  Future<void> _startTrip() async {
    if (!_canDepart || _tripId.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_trip['status'] == 'arrived_at_pickup') {
        _trip = await _api.updateTrip(
          _tripId,
          'loaded',
          body: _collectAtPickup ? {'cashCollected': _cashCollected} : const {},
        );
      }
      _trip = await _api.updateTrip(
        _tripId,
        'depart',
        body: {'vehicleFit': _vehicleFit},
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ProofOfDeliveryScreen(trip: _trip, api: widget.api),
        ),
      );
    } catch (error) {
      if (!mounted || handleDriverSessionError(context, error)) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelTrip() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this trip?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep trip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Cancel trip'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !mounted) return;
    if (reason.isEmpty) {
      setState(() => _error = 'Enter a reason to cancel the trip.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.cancelTrip(_tripId, reason);
      if (mounted) Navigator.of(context).pop();
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
    final pickup = (_trip['pickup'] as Map?)?['address'] ?? 'Pickup';
    final dropoff = (_trip['dropoff'] as Map?)?['address'] ?? 'Drop-off';
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DriverPageHeader(
                      label: 'Ready to start the trip',
                      progress: 'Trip $_tripId',
                    ),
                    const Text(
                      'Confirm the loaded cargo',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Pickup: $pickup\n\nDrop-off: $dropoff\n\n'
                        '${_trip['itemCount'] ?? 0} items · '
                        '${_trip['weightKg'] ?? 0} kg',
                        style: const TextStyle(height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Pickup evidence · ${_pickupPhotos.length}/6 photos',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _busy ? null : _addPickupPhoto,
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Add photo'),
                        ),
                      ],
                    ),
                    if (_pickupPhotos.isEmpty)
                      const Text(
                        'At least one cargo photo is required before loading.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    const SizedBox(height: 14),
                    const Text(
                      'How does the vehicle fit the cargo?',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final fit in const [
                          ('suitable', 'Suitable'),
                          ('too_small', 'Too small'),
                          ('too_large', 'Too large'),
                        ])
                          ChoiceChip(
                            label: Text(fit.$2),
                            selected: _vehicleFit == fit.$1,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _vehicleFit = fit.$1);
                              }
                            },
                          ),
                      ],
                    ),
                    if (_collectAtPickup) ...[
                      const SizedBox(height: 14),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _cashCollected,
                        onChanged: _busy
                            ? null
                            : (value) => setState(
                                () => _cashCollected = value ?? false,
                              ),
                        title: Text(
                          'Cash collected from sender · EGP '
                          '${_cashToCollect.toStringAsFixed(2)}',
                        ),
                      ),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PrimaryButton(
                    label: _busy ? 'Updating trip...' : 'Start trip',
                    onPressed: _canDepart ? _startTrip : null,
                  ),
                  if (_trip['status'] != 'loaded')
                    TextButton(
                      onPressed: _busy ? null : _cancelTrip,
                      child: const Text('Cancel trip'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
