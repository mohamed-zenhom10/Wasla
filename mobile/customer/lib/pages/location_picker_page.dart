import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:main/components/main_button.dart';
import 'package:main/theme/app_theme.dart';

class PickedLocation {
  const PickedLocation({required this.address, required this.point});

  final String address;
  final LatLng point;
}

class _PlaceResult {
  const _PlaceResult(this.name, this.point);

  final String name;
  final LatLng point;
}

class LocationException implements Exception {
  const LocationException(this.message, {this.openSettings = false});

  final String message;
  final bool openSettings;
}

class LocationService {
  static const _headers = {'Accept': 'application/json'};
  static const _host = 'nominatim.openstreetmap.org';

  static Future<LatLng> currentLatLng() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw const LocationException(
        'Location is turned off. Please turn it on.',
        openSettings: true,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException('Location permission was denied.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Location permission is blocked. Enable it from app settings.',
        openSettings: true,
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return LatLng(position.latitude, position.longitude);
  }

  static Future<String> reverse(LatLng point) async {
    final uri = Uri.https(_host, '/reverse', {
      'format': 'jsonv2',
      'lat': '${point.latitude}',
      'lon': '${point.longitude}',
      'accept-language': 'en',
    });
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Reverse failed');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final name = (data['display_name'] as String?) ?? '';
    return name.split(',').take(3).map((e) => e.trim()).join(', ');
  }

  static Future<List<_PlaceResult>> search(String query) async {
    final uri = Uri.https(_host, '/search', {
      'format': 'jsonv2',
      'q': query,
      'limit': '6',
      'countrycodes': 'eg',
      'accept-language': 'en',
    });
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return const [];
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((item) {
      final map = item as Map<String, dynamic>;
      return _PlaceResult(
        (map['display_name'] as String).split(',').take(3).join(', ').trim(),
        LatLng(
          double.parse(map['lat'] as String),
          double.parse(map['lon'] as String),
        ),
      );
    }).toList();
  }
}

class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key, required this.title, this.initialPoint});

  final String title;
  final LatLng? initialPoint;

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  static const _cairo = LatLng(30.0444, 31.2357);

  final _mapController = MapController();
  final _searchController = TextEditingController();
  Timer? _reverseDebounce;
  Timer? _searchDebounce;

  late LatLng _center = widget.initialPoint ?? _cairo;
  String _address = '';
  bool _loadingAddress = false;
  bool _locating = false;
  List<_PlaceResult> _results = const [];

  @override
  void initState() {
    super.initState();
    if (widget.initialPoint == null) {
      _goToMyLocation(silent: true);
    } else {
      _reverseGeocode();
    }
  }

  @override
  void dispose() {
    _reverseDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _center = camera.center;
    if (!hasGesture) return;
    _reverseDebounce?.cancel();
    setState(() => _loadingAddress = true);
    _reverseDebounce = Timer(
      const Duration(milliseconds: 700),
      _reverseGeocode,
    );
  }

  Future<void> _reverseGeocode() async {
    final point = _center;
    if (mounted) setState(() => _loadingAddress = true);
    try {
      final address = await LocationService.reverse(point);
      if (!mounted || point != _center) return;
      setState(() {
        _address = address.isEmpty ? 'Selected location' : address;
        _loadingAddress = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _address =
            '${point.latitude.toStringAsFixed(5)}, '
            '${point.longitude.toStringAsFixed(5)}';
        _loadingAddress = false;
      });
    }
  }

  Future<void> _goToMyLocation({bool silent = false}) async {
    setState(() => _locating = true);
    try {
      final point = await LocationService.currentLatLng();
      if (!mounted) return;
      _center = point;
      _mapController.move(point, 16);
      await _reverseGeocode();
    } on LocationException catch (error) {
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          action: error.openSettings
              ? SnackBarAction(
                  label: 'Settings',
                  onPressed: Geolocator.openLocationSettings,
                )
              : null,
        ),
      );
    } catch (_) {
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get your location.')),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _results = const []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        final results = await LocationService.search(value.trim());
        if (mounted) setState(() => _results = results);
      } catch (_) {}
    });
  }

  void _selectResult(_PlaceResult result) {
    FocusScope.of(context).unfocus();
    _searchController.clear();
    _center = result.point;
    _mapController.move(result.point, 16);
    setState(() {
      _results = const [];
      _address = result.name;
      _loadingAddress = false;
    });
  }

  void _confirm() {
    Navigator.of(context).pop(
      PickedLocation(
        address: _address.isEmpty ? 'Selected location' : _address,
        point: _center,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15,
              onPositionChanged: _onPositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.main',
              ),
            ],
          ),

          // Center pin (the tip sits exactly on the map center)
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 44),
                child: Icon(
                  Icons.location_on,
                  size: 44,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),

          // Top: back button + search + results
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Material(
                        color: AppColors.white,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: IconButton(
                          tooltip: 'Back',
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Material(
                          color: AppColors.white,
                          elevation: 2,
                          borderRadius: BorderRadius.circular(12),
                          child: TextField(
                            controller: _searchController,
                            onChanged: _onSearchChanged,
                            style: const TextStyle(
                              color: AppColors.darkGreen,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search ${widget.title.toLowerCase()}',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_results.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(blurRadius: 8, color: Color(0x22000000)),
                        ],
                      ),
                      child: Column(
                        children: [
                          for (final result in _results)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.place_outlined),
                              title: Text(
                                result.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _selectResult(result),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // My-location button
          Positioned(
            right: 16,
            bottom: 190,
            child: Material(
              color: AppColors.white,
              shape: const CircleBorder(),
              elevation: 3,
              child: IconButton(
                tooltip: 'My location',
                onPressed: _locating ? null : _goToMyLocation,
                icon: _locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location, color: AppColors.darkGreen),
              ),
            ),
          ),

          // Bottom confirm card
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
              decoration: const BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(blurRadius: 12, color: Color(0x22000000)),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: AppColors.darkGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _loadingAddress
                                ? 'Finding address...'
                                : (_address.isEmpty
                                      ? 'Move the map to choose'
                                      : _address),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.darkGreen,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    MainButton(
                      text: 'Confirm location',
                      onPressed: (_loadingAddress || _address.isEmpty)
                          ? null
                          : _confirm,
                      borderRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
