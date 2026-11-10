import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:main/components/main_button.dart';
import 'package:main/theme/app_theme.dart';

class PickedLocation {
  const PickedLocation({required this.address, required this.point});

  final String address;
  final LatLng point;
}

class _Suggestion {
  const _Suggestion({
    required this.title,
    required this.subtitle,
    required this.label,
    required this.point,
  });

  /// Main line shown in the results list (place name).
  final String title;

  /// Second line (area / city).
  final String subtitle;

  /// Text written in the field after selecting (name + area).
  final String label;
  final LatLng point;
}

class LocationException implements Exception {
  const LocationException(this.message, {this.openSettings = false});

  final String message;
  final bool openSettings;
}

class LocationService {
  // ---------- Device location ----------
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

  static String? _clean(dynamic value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static String _join(Iterable<String?> parts, {int max = 3}) {
    final seen = <String>{};
    final result = <String>[];
    for (final part in parts) {
      if (part == null) continue;
      if (seen.add(part.toLowerCase())) result.add(part);
      if (result.length == max) break;
    }
    return result.join(', ');
  }

  // ---------- Search (Photon, OpenStreetMap data) ----------
  static Future<List<_Suggestion>> search(String query, LatLng bias) async {
    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': query,
      'limit': '8',
      'lang': 'en',
      'lat': '${bias.latitude}',
      'lon': '${bias.longitude}',
      // Egypt only: minLon,minLat,maxLon,maxLat
      'bbox': '24.5,21.5,37.0,32.0',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return const [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final features = (data['features'] as List<dynamic>?) ?? const [];
    final results = <_Suggestion>[];
    final seenLabels = <String>{};

    for (final item in features) {
      final feature = item as Map<String, dynamic>;
      final props = (feature['properties'] as Map<String, dynamic>?) ?? {};
      final coords = (feature['geometry']?['coordinates'] as List<dynamic>?);
      if (coords == null || coords.length < 2) continue;

      final name = _clean(props['name']);
      final street = _clean(props['street']);
      final house = _clean(props['housenumber']);
      final district = _clean(props['district']) ?? _clean(props['locality']);
      final city = _clean(props['city']);
      final state = _clean(props['state']);

      final streetLine = street == null
          ? null
          : (house == null ? street : '$street $house');
      final title = name ?? streetLine ?? district ?? city;
      if (title == null) continue;

      final subtitle = _join(
        [
          if (name != null) streetLine,
          district,
          city,
          state,
        ].where((part) => part != null && part != title),
      );

      final area = district ?? city;
      final label = _join([title, area != title ? area : null], max: 2);
      if (!seenLabels.add(label.toLowerCase())) continue;

      results.add(
        _Suggestion(
          title: title,
          subtitle: subtitle,
          label: label,
          point: LatLng(
            (coords[1] as num).toDouble(),
            (coords[0] as num).toDouble(),
          ),
        ),
      );
    }
    return results;
  }

  // ---------- Reverse geocoding: always a name, never coordinates ----------
  static Future<String> reverse(LatLng point) async {
    try {
      final name = await _nominatimReverse(point);
      if (name.isNotEmpty) return name;
    } catch (_) {}
    try {
      final name = await _photonReverse(point);
      if (name.isNotEmpty) return name;
    } catch (_) {}
    return '';
  }

  static Future<String> _nominatimReverse(LatLng point) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': '${point.latitude}',
      'lon': '${point.longitude}',
      'zoom': '18',
      'addressdetails': '1',
      'accept-language': 'en',
    });
    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return '';

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final address = (data['address'] as Map<String, dynamic>?) ?? {};

    final first =
        _clean(data['name']) ??
        _clean(address['road']) ??
        _clean(address['pedestrian']) ??
        _clean(address['amenity']);
    final area =
        _clean(address['suburb']) ??
        _clean(address['neighbourhood']) ??
        _clean(address['quarter']) ??
        _clean(address['city_district']);
    final city =
        _clean(address['city']) ??
        _clean(address['town']) ??
        _clean(address['village']) ??
        _clean(address['state']);

    final built = _join([first, area, city]);
    if (built.isNotEmpty) return built;

    final display = _clean(data['display_name']);
    if (display == null) return '';
    return _join(display.split(',').map((part) => _clean(part)));
  }

  static Future<String> _photonReverse(LatLng point) async {
    final uri = Uri.https('photon.komoot.io', '/reverse', {
      'lat': '${point.latitude}',
      'lon': '${point.longitude}',
      'lang': 'en',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return '';

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final features = (data['features'] as List<dynamic>?) ?? const [];
    if (features.isEmpty) return '';
    final props =
        ((features.first as Map<String, dynamic>)['properties']
            as Map<String, dynamic>?) ??
        {};
    return _join([
      _clean(props['name']) ?? _clean(props['street']),
      _clean(props['district']) ?? _clean(props['locality']),
      _clean(props['city']) ?? _clean(props['state']),
    ]);
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
  bool _searching = false;
  List<_Suggestion> _suggestions = const [];

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

  // Only user drags trigger a new address lookup. Moves caused by search or
  // "my location" set the address themselves.
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
    final name = await LocationService.reverse(point);
    if (!mounted || point != _center) return;
    setState(() {
      _address = name.isEmpty ? 'Selected location' : name;
      _loadingAddress = false;
    });
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
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _suggestions = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final results = await LocationService.search(query, _center);
        if (!mounted) return;
        setState(() {
          _suggestions = results;
          _searching = false;
        });
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _selectSuggestion(_Suggestion suggestion) {
    FocusScope.of(context).unfocus();
    _searchController.clear();
    _reverseDebounce?.cancel();
    _center = suggestion.point;
    _mapController.move(suggestion.point, 17);
    setState(() {
      _suggestions = const [];
      _address = suggestion.label;
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
    final hasQuery = _searchController.text.trim().length >= 2;

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

          // Center pin (its tip sits on the map center)
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
                              suffixIcon: _searching
                                  ? const Padding(
                                      padding: EdgeInsets.all(14),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : null,
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
                  if (_suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(maxHeight: 320),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(blurRadius: 8, color: Color(0x22000000)),
                        ],
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final suggestion in _suggestions)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.place_outlined),
                              title: Text(
                                suggestion.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: suggestion.subtitle.isEmpty
                                  ? null
                                  : Text(
                                      suggestion.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              onTap: () => _selectSuggestion(suggestion),
                            ),
                        ],
                      ),
                    )
                  else if (hasQuery && !_searching)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(blurRadius: 8, color: Color(0x22000000)),
                        ],
                      ),
                      child: const Text(
                        'No places found. Try another name.',
                        style: TextStyle(
                          color: AppColors.darkGreen,
                          fontSize: 13,
                        ),
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
