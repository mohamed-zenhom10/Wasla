import 'dart:async';
import 'dart:math' as math;

import 'package:driver/data/route_deviation_tracker.dart';
import 'package:driver/data/tomtom_routing_service.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class MapPlace {
  const MapPlace({required this.label, required this.point, this.address});

  final String label;
  final LatLng point;
  final String? address;

  static MapPlace? fromJson(Object? value, String label) {
    if (value is! Map) return null;
    final latitude = _coordinate(value['lat']);
    final longitude = _coordinate(value['lng']);
    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }
    return MapPlace(
      label: label,
      point: LatLng(latitude, longitude),
      address: value['address']?.toString(),
    );
  }

  static double? _coordinate(Object? value) {
    final result = value is num ? value.toDouble() : double.tryParse('$value');
    return result != null && result.isFinite ? result : null;
  }
}

class DriverMapPreview extends StatelessWidget {
  const DriverMapPreview({super.key, this.height = 272, this.isOnline});

  final double height;
  final bool? isOnline;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DriverNavigationMap(
        trackCurrentLocation: false,
        showNavigationPanel: false,
        stageLabel: isOnline == true ? 'Online · TomTom map' : 'TomTom map',
      ),
    ),
  );
}

class DriverNavigationMap extends StatefulWidget {
  const DriverNavigationMap({
    super.key,
    required this.trackCurrentLocation,
    required this.showNavigationPanel,
    required this.stageLabel,
    this.routeRequired = false,
    this.allowDestinationSearch = false,
    this.destination,
    this.pickup,
    this.dropoff,
    this.height,
  });

  final bool trackCurrentLocation;
  final bool showNavigationPanel;
  final String stageLabel;
  final bool routeRequired;
  final bool allowDestinationSearch;
  final MapPlace? destination;
  final MapPlace? pickup;
  final MapPlace? dropoff;
  final double? height;

  @override
  State<DriverNavigationMap> createState() => _DriverNavigationMapState();
}

class _DriverNavigationMapState extends State<DriverNavigationMap> {
  static const _fallbackCenter = LatLng(30.0444, 31.2357);
  static const _offRouteThresholdMeters = 75.0;

  final _mapController = MapController();
  final _routing = TomTomRoutingService();
  final _speech = FlutterTts();
  final _destinationController = TextEditingController();
  final _deviationTracker = RouteDeviationTracker(
    minimumDistanceMeters: _offRouteThresholdMeters,
  );
  StreamSubscription<Position>? _positionSubscription;
  Timer? _searchDebounce;
  Timer? _offRouteTimer;
  Position? _position;
  TomTomRoute? _route;
  MapPlace? _destinationOverride;
  List<TomTomSearchResult> _searchResults = const [];
  String? _error;
  String? _searchError;
  String? _tileError;
  String? _voiceError;
  bool _loadingRoute = false;
  bool _searchingPlaces = false;
  bool _mapReady = false;
  bool _followDriver = true;
  bool _voiceEnabled = true;
  bool _hasFittedRoute = false;
  bool _hasRequestedInitialRoute = false;
  bool _showRecalculateButton = false;
  bool _routeRequestFailed = false;
  int _nextInstruction = 0;
  int _remainingSeconds = 0;
  int _routeRequestGeneration = 0;
  int _searchGeneration = 0;

  MapPlace? get _activeDestination =>
      _destinationOverride ?? widget.destination;

  void _onDestinationQueryChanged(String query) {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (_destinationOverride != null) {
      _routeRequestGeneration++;
      setState(() {
        _destinationOverride = null;
        _route = null;
        _loadingRoute = false;
        _nextInstruction = 0;
        _hasFittedRoute = false;
        _hasRequestedInitialRoute = false;
        _routeRequestFailed = false;
        _resetOffRouteState();
        _searchResults = const [];
        _searchError = null;
      });
    } else {
      setState(() {
        _searchResults = const [];
        _searchError = null;
      });
    }

    if (trimmed.length < 2) {
      setState(() => _searchingPlaces = false);
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 550),
      () => _searchPlaces(trimmed),
    );
  }

  Future<void> _searchPlaces(String query) async {
    final generation = ++_searchGeneration;
    setState(() {
      _searchingPlaces = true;
      _searchError = null;
    });
    try {
      final results = await _routing.searchPlaces(query);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchResults = results;
        _searchingPlaces = false;
        if (results.isEmpty) {
          _searchError = 'مفيش أماكن مطابقة. جرّب اسمًا أوضح.';
        }
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchingPlaces = false;
        _searchError = error.toString();
      });
    }
  }

  void _selectDestination(TomTomSearchResult result) {
    _searchDebounce?.cancel();
    _searchGeneration++;
    final destination = MapPlace(
      label: result.name,
      address: result.address,
      point: result.point,
    );
    setState(() {
      _destinationOverride = destination;
      _destinationController.text = result.name;
      _searchResults = const [];
      _searchError = null;
      _searchingPlaces = false;
      _routeRequestGeneration++;
      _route = null;
      _loadingRoute = false;
      _hasRequestedInitialRoute = false;
      _routeRequestFailed = false;
      _nextInstruction = 0;
      _hasFittedRoute = false;
    });
    _resetOffRouteState();
    _refreshRoute();
  }

  @override
  void initState() {
    super.initState();
    if (widget.showNavigationPanel) _prepareVoice();
    if (widget.trackCurrentLocation) _startTracking();
  }

  @override
  void didUpdateWidget(covariant DriverNavigationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.trackCurrentLocation && widget.trackCurrentLocation) {
      _startTracking();
    } else if (oldWidget.trackCurrentLocation && !widget.trackCurrentLocation) {
      _stopTracking();
    }
    if (oldWidget.destination?.point != widget.destination?.point &&
        _destinationOverride == null) {
      _routeRequestGeneration++;
      _route = null;
      _loadingRoute = false;
      _hasRequestedInitialRoute = false;
      _routeRequestFailed = false;
      _nextInstruction = 0;
      _hasFittedRoute = false;
      _resetOffRouteState();
      _refreshRoute();
    }
  }

  Future<void> _prepareVoice() async {
    try {
      await _speech.setLanguage('ar');
      await _speech.setSpeechRate(0.48);
    } catch (error) {
      if (mounted) {
        setState(() {
          _voiceEnabled = false;
          _voiceError = 'Voice guidance is unavailable: $error';
        });
      }
    }
  }

  Future<void> _startTracking() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Turn on device location to navigate.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError(
          permission == LocationPermission.deniedForever
              ? 'Allow location access in device settings to navigate.'
              : 'Allow location access to start navigation.',
        );
      }

      final initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      _onPosition(initialPosition);
      await _positionSubscription?.cancel();
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            ),
          ).listen(
            _onPosition,
            onError: (Object error) {
              _offRouteTimer?.cancel();
              _offRouteTimer = null;
              _deviationTracker.reset();
              if (mounted) {
                setState(() {
                  _error = 'GPS signal lost: $error';
                  _showRecalculateButton = false;
                });
              }
            },
          );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    final route = _route;
    setState(() {
      _position = position;
      if (route != null) {
        _remainingSeconds = _remainingRouteSeconds(position, route);
      }
      if (_error?.startsWith('GPS signal lost:') == true) _error = null;
    });
    if (_mapReady && _followDriver) {
      final zoom = _mapController.camera.zoom.clamp(13.0, 16.0).toDouble();
      _mapController.move(LatLng(position.latitude, position.longitude), zoom);
    }
    if (_route == null && !_hasRequestedInitialRoute) {
      _refreshRoute();
    } else {
      _checkRouteDeviation(position);
      _announceNextInstruction(position);
    }
  }

  Future<void> _refreshRoute() async {
    final destination = _activeDestination;
    final position = _position;
    if (!widget.trackCurrentLocation ||
        destination == null ||
        position == null ||
        _loadingRoute) {
      return;
    }
    setState(() {
      _loadingRoute = true;
      _error = null;
      _routeRequestFailed = false;
    });
    _hasRequestedInitialRoute = true;
    final requestGeneration = ++_routeRequestGeneration;
    try {
      final route = await _routing.calculateFastestRoute(
        origin: LatLng(position.latitude, position.longitude),
        destination: destination.point,
      );
      if (!mounted || requestGeneration != _routeRequestGeneration) return;
      setState(() {
        _route = route;
        _loadingRoute = false;
        _nextInstruction = 0;
        _remainingSeconds = _remainingRouteSeconds(
          _position ?? position,
          route,
        );
      });
      _resetOffRouteState();
      _fitRouteOnce(route);
      _announceNextInstruction(_position ?? position);
    } catch (error) {
      if (!mounted || requestGeneration != _routeRequestGeneration) return;
      setState(() {
        _loadingRoute = false;
        _error = error.toString();
        _routeRequestFailed = true;
      });
    }
  }

  void _checkRouteDeviation(Position position) {
    final route = _route;
    if (route == null) return;
    final distance = _distanceFromRoute(
      LatLng(position.latitude, position.longitude),
      route.points,
    );
    final shouldPrompt = _deviationTracker.update(
      distanceMeters: distance,
      accuracyMeters: position.accuracy,
      now: DateTime.now(),
    );
    if (!_deviationTracker.isOffRoute) {
      _offRouteTimer?.cancel();
      _offRouteTimer = null;
      if (_showRecalculateButton) {
        setState(() => _showRecalculateButton = false);
      }
      return;
    }

    if (shouldPrompt) {
      _offRouteTimer?.cancel();
      _offRouteTimer = null;
      if (!_showRecalculateButton) {
        setState(() => _showRecalculateButton = true);
      }
    } else if (!_showRecalculateButton && _offRouteTimer == null) {
      _offRouteTimer = Timer(
        _deviationTracker.timeUntilPrompt(DateTime.now()),
        () {
          _offRouteTimer = null;
          if (mounted && _deviationTracker.isOffRoute) {
            setState(() => _showRecalculateButton = true);
          }
        },
      );
    }
  }

  void _resetOffRouteState() {
    _offRouteTimer?.cancel();
    _offRouteTimer = null;
    _deviationTracker.reset();
    _showRecalculateButton = false;
  }

  int _remainingRouteSeconds(Position position, TomTomRoute route) {
    final points = route.points;
    if (points.length < 2) return route.durationSeconds;

    var closestPointIndex = 0;
    var closestPointDistance = double.infinity;
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        point.latitude,
        point.longitude,
      );
      if (distance < closestPointDistance) {
        closestPointDistance = distance;
        closestPointIndex = index;
      }
    }

    var totalDistance = 0.0;
    var remainingDistance = 0.0;
    for (var index = 0; index < points.length - 1; index++) {
      final start = points[index];
      final end = points[index + 1];
      final segmentDistance = Geolocator.distanceBetween(
        start.latitude,
        start.longitude,
        end.latitude,
        end.longitude,
      );
      totalDistance += segmentDistance;
      if (index >= closestPointIndex) remainingDistance += segmentDistance;
    }
    if (totalDistance == 0) return route.durationSeconds;
    final remainingFraction = (remainingDistance / totalDistance).clamp(0, 1);
    return (route.durationSeconds * remainingFraction).round();
  }

  void _announceNextInstruction(Position position) {
    if (!_voiceEnabled || _route == null) return;
    final instructions = _route!.instructions;
    var nextInstruction = _nextInstruction;
    while (nextInstruction < instructions.length) {
      final instruction = instructions[nextInstruction];
      final point = instruction.point;
      if (point == null) {
        nextInstruction++;
        continue;
      }
      if (Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            point.latitude,
            point.longitude,
          ) >
          65) {
        break;
      }
      nextInstruction++;
      unawaited(_speak(instruction.message));
    }
    if (nextInstruction != _nextInstruction && mounted) {
      setState(() => _nextInstruction = nextInstruction);
    }
  }

  void _setVoiceEnabled(bool enabled) {
    setState(() => _voiceEnabled = enabled);
    if (!enabled) unawaited(_speech.stop());
  }

  Future<void> _speak(String message) async {
    try {
      await _speech.speak(message);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _voiceEnabled = false;
        _voiceError = 'Voice guidance is unavailable: $error';
      });
    }
  }

  void _onTileError(Object _) {
    if (!mounted || _tileError != null) return;
    setState(
      () => _tileError =
          'TomTom map tiles could not be loaded. Check connectivity and key settings.',
    );
  }

  void _fitRouteOnce(TomTomRoute route) {
    if (!_mapReady || _hasFittedRoute || !_followDriver) return;
    _hasFittedRoute = true;
    final points = <LatLng>[
      ...route.points,
      if (_position case final position?)
        LatLng(position.latitude, position.longitude),
    ];
    if (points.length < 2) return;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(52),
      ),
    );
  }

  Future<void> _recenter() async {
    final position = _position;
    if (position == null) {
      await _startTracking();
      return;
    }
    _followDriver = true;
    _mapController.move(LatLng(position.latitude, position.longitude), 15);
  }

  double _distanceFromRoute(LatLng point, List<LatLng> line) {
    if (line.isEmpty) return double.infinity;
    if (line.length == 1) {
      return Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        line.first.latitude,
        line.first.longitude,
      );
    }
    final latitudeScale = 110540.0;
    final longitudeScale = 111320.0 * math.cos(point.latitude * math.pi / 180);
    var closest = double.infinity;
    for (var index = 0; index < line.length - 1; index++) {
      final start = line[index];
      final end = line[index + 1];
      final startX = (start.longitude - point.longitude) * longitudeScale;
      final startY = (start.latitude - point.latitude) * latitudeScale;
      final endX = (end.longitude - point.longitude) * longitudeScale;
      final endY = (end.latitude - point.latitude) * latitudeScale;
      final dx = endX - startX;
      final dy = endY - startY;
      final denominator = dx * dx + dy * dy;
      final offset = denominator == 0
          ? 0.0
          : (-(startX * dx + startY * dy) / denominator).clamp(0.0, 1.0);
      final distance = math.sqrt(
        math.pow(startX + offset * dx, 2) + math.pow(startY + offset * dy, 2),
      );
      closest = math.min(closest, distance);
    }
    return closest;
  }

  @override
  void dispose() {
    _routeRequestGeneration++;
    _stopTracking();
    _searchDebounce?.cancel();
    _offRouteTimer?.cancel();
    _destinationController.dispose();
    _routing.close();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final destination = _activeDestination;
    final trafficEnabled = destination != null && _route != null;
    final missingCoordinates = widget.routeRequired && destination == null;
    final mapError = _error ?? _voiceError ?? _tileError;
    final child = Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _position == null
                  ? destination?.point ?? _fallbackCenter
                  : LatLng(_position!.latitude, _position!.longitude),
              initialZoom: 13,
              minZoom: 3,
              maxZoom: 19,
              onPositionChanged: (_, hasGesture) {
                if (hasGesture) _followDriver = false;
              },
              onMapReady: () {
                _mapReady = true;
                final route = _route;
                if (route != null) _fitRouteOnce(route);
              },
            ),
            children: [
              if (TomTomRoutingService.apiKey.isNotEmpty)
                TileLayer(
                  urlTemplate:
                      'https://api.tomtom.com/map/1/tile/basic/night/'
                      '{z}/{x}/{y}.png?view=Unified&tileSize=512&key={key}',
                  additionalOptions: {'key': TomTomRoutingService.apiKey},
                  userAgentPackageName: 'com.wasla.driver',
                  tileDimension: 512,
                  zoomOffset: -1,
                  maxNativeZoom: 19,
                  keepBuffer: 2,
                  panBuffer: 0,
                  errorTileCallback: (_, error, _) => _onTileError(error),
                ),
              if (trafficEnabled)
                Opacity(
                  opacity: 0.58,
                  child: TileLayer(
                    urlTemplate:
                        'https://api.tomtom.com/traffic/map/4/tile/flow/relative/'
                        '{z}/{x}/{y}.png?tileSize=512&key={key}',
                    additionalOptions: {'key': TomTomRoutingService.apiKey},
                    userAgentPackageName: 'com.wasla.driver',
                    tileDimension: 512,
                    zoomOffset: -1,
                    maxNativeZoom: 18,
                    keepBuffer: 2,
                    panBuffer: 0,
                    errorTileCallback: (_, error, _) => _onTileError(error),
                  ),
                ),
              if (_route case final route?)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: route.points,
                      strokeWidth: 8,
                      color: const Color(0xFF55E6B1),
                      borderStrokeWidth: 2.5,
                      borderColor: const Color(0xFF101820),
                    ),
                  ],
                ),
              MarkerLayer(markers: _markers()),
            ],
          ),
        ),
        if (widget.allowDestinationSearch)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _DestinationSearch(
              controller: _destinationController,
              searching: _searchingPlaces,
              error: _searchError,
              results: _searchResults,
              onChanged: _onDestinationQueryChanged,
              onSelected: _selectDestination,
            ),
          ),
        if (!widget.allowDestinationSearch || _searchResults.isEmpty)
          Positioned(
            top: widget.allowDestinationSearch ? 78 : 14,
            left: 14,
            child: _MapBadge(
              icon: Icons.route,
              label: widget.allowDestinationSearch && destination == null
                  ? 'حدد وجهتك'
                  : widget.stageLabel,
            ),
          ),
        if (!widget.allowDestinationSearch || _searchResults.isEmpty)
          Positioned(
            top: widget.allowDestinationSearch ? 78 : 14,
            right: 14,
            child: _MapControl(
              tooltip: 'Center on driver',
              icon: Icons.my_location,
              onPressed: _recenter,
            ),
          ),
        if (trafficEnabled &&
            (!widget.allowDestinationSearch || _searchResults.isEmpty))
          Positioned(
            left: 14,
            top: widget.allowDestinationSearch ? 124 : 60,
            child: const _MapBadge(
              icon: Icons.traffic,
              label: 'Live traffic',
              compact: true,
            ),
          ),
        Positioned(
          left: 14,
          bottom: widget.showNavigationPanel ? 146 : 8,
          child: const Text(
            '© TomTom',
            style: TextStyle(
              color: Color(0xFFF3F7FA),
              fontSize: 10,
              shadows: [Shadow(color: Colors.black, blurRadius: 5)],
            ),
          ),
        ),
        if (TomTomRoutingService.apiKey.isEmpty ||
            mapError != null ||
            missingCoordinates)
          Positioned(
            left: 14,
            right: 14,
            top: widget.allowDestinationSearch ? 124 : 60,
            child: _ErrorBanner(
              message: TomTomRoutingService.apiKey.isEmpty
                  ? 'TomTom API key is required to load map tiles and routing.'
                  : mapError ??
                        (missingCoordinates
                            ? 'This trip is missing its destination coordinates. Refresh the trip.'
                            : null) ??
                        'Map services could not be loaded. Check connectivity.',
            ),
          ),
        if (_loadingRoute)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 3),
          ),
        if (widget.showNavigationPanel)
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: _NavigationPanel(
              route: _route,
              instructionIndex: _nextInstruction,
              remainingSeconds: _remainingSeconds,
              loading: _loadingRoute,
              showRecalculate: _showRecalculateButton || _routeRequestFailed,
              recalculateLabel: _routeRequestFailed && _route == null
                  ? 'إعادة المحاولة'
                  : 'إعادة حساب الطريق',
              onRecalculate: _refreshRoute,
              voiceEnabled: _voiceEnabled,
              onVoiceChanged: _setVoiceEnabled,
              error: _error,
              waitingForDestination:
                  widget.allowDestinationSearch && destination == null,
            ),
          ),
      ],
    );
    return widget.height == null
        ? child
        : SizedBox(height: widget.height, child: child);
  }

  List<Marker> _markers() {
    final markers = <Marker>[];
    final position = _position;
    if (position != null) {
      markers.add(
        Marker(
          point: LatLng(position.latitude, position.longitude),
          width: 44,
          height: 44,
          child: const _LocationDot(),
        ),
      );
    }
    if (widget.pickup case final pickup?) {
      markers.add(
        Marker(
          point: pickup.point,
          width: 48,
          height: 58,
          alignment: Alignment.topCenter,
          child: const _PlacePin(
            icon: Icons.storefront,
            color: Color(0xFF1F8A70),
          ),
        ),
      );
    }
    if (widget.dropoff case final dropoff?) {
      markers.add(
        Marker(
          point: dropoff.point,
          width: 48,
          height: 58,
          alignment: Alignment.topCenter,
          child: const _PlacePin(icon: Icons.flag, color: AppColors.accent),
        ),
      );
    }
    if (_destinationOverride case final destination?) {
      markers.add(
        Marker(
          point: destination.point,
          width: 48,
          height: 58,
          alignment: Alignment.topCenter,
          child: const _PlacePin(icon: Icons.near_me, color: Color(0xFF55E6B1)),
        ),
      );
    }
    return markers;
  }
}

class _MapBadge extends StatelessWidget {
  const _MapBadge({
    required this.icon,
    required this.label,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 10 : 12,
      vertical: compact ? 7 : 9,
    ),
    decoration: BoxDecoration(
      color: const Color(0xF20E1721),
      border: Border.all(color: const Color(0xFF2C3946)),
      borderRadius: BorderRadius.circular(13),
      boxShadow: const [
        BoxShadow(
          color: Color(0x44000000),
          blurRadius: 12,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF55E6B1)),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFF3F7FA),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _MapControl extends StatelessWidget {
  const _MapControl({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF111B25),
    shape: const CircleBorder(),
    elevation: 3,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: const Color(0xFF55E6B1)),
    ),
  );
}

class _DestinationSearch extends StatelessWidget {
  const _DestinationSearch({
    required this.controller,
    required this.searching,
    required this.error,
    required this.results,
    required this.onChanged,
    required this.onSelected,
  });

  final TextEditingController controller;
  final bool searching;
  final String? error;
  final List<TomTomSearchResult> results;
  final ValueChanged<String> onChanged;
  final ValueChanged<TomTomSearchResult> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        decoration: BoxDecoration(
          color: const Color(0xFF111B25),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFF2C3946)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 22,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(color: Color(0xFFF3F7FA), fontSize: 15),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'رايح فين؟ مثال: عين شمس',
            hintStyle: const TextStyle(color: Color(0xFF8997A5)),
            prefixIcon: const Icon(Icons.search, color: Color(0xFF55E6B1)),
            suffixIcon: searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : controller.text.isNotEmpty
                ? IconButton(
                    tooltip: 'مسح الوجهة',
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                    icon: const Icon(Icons.close, color: Color(0xFF8997A5)),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 17),
          ),
        ),
      ),
      if (results.isNotEmpty || error != null)
        Container(
          margin: const EdgeInsets.only(top: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF111B25),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFF2C3946)),
          ),
          child: results.isNotEmpty
              ? ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const Divider(
                    height: 1,
                    indent: 54,
                    color: Color(0xFF2C3946),
                  ),
                  itemBuilder: (context, index) {
                    final result = results[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.location_on_outlined,
                        color: Color(0xFF55E6B1),
                      ),
                      title: Text(
                        result.name,
                        style: const TextStyle(color: Color(0xFFF3F7FA)),
                      ),
                      subtitle: result.address.isEmpty
                          ? null
                          : Text(
                              result.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF8997A5)),
                            ),
                      onTap: () => onSelected(result),
                    );
                  },
                )
              : Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Color(0xFFE7A19A)),
                  ),
                ),
        ),
    ],
  );
}

class _LocationDot extends StatelessWidget {
  const _LocationDot();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: const Color(0xFF2878F0),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 8, spreadRadius: 2),
        ],
      ),
    ),
  );
}

class _PlacePin extends StatelessWidget {
  const _PlacePin({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Icon(
    icon,
    color: color,
    size: 38,
    shadows: const [Shadow(color: Colors.white, blurRadius: 7)],
  );
}

class _NavigationPanel extends StatelessWidget {
  const _NavigationPanel({
    required this.route,
    required this.instructionIndex,
    required this.remainingSeconds,
    required this.loading,
    required this.showRecalculate,
    required this.recalculateLabel,
    required this.onRecalculate,
    required this.voiceEnabled,
    required this.onVoiceChanged,
    required this.error,
    required this.waitingForDestination,
  });

  final TomTomRoute? route;
  final int instructionIndex;
  final int remainingSeconds;
  final bool loading;
  final bool showRecalculate;
  final String recalculateLabel;
  final VoidCallback onRecalculate;
  final bool voiceEnabled;
  final ValueChanged<bool> onVoiceChanged;
  final String? error;
  final bool waitingForDestination;

  String _duration(int seconds) {
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${minutes % 60} min';
  }

  String _distance(int meters) =>
      meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '$meters m';

  String _eta(int durationSeconds) {
    final arrival = DateTime.now().add(Duration(seconds: durationSeconds));
    final hour = arrival.hour % 12 == 0 ? 12 : arrival.hour % 12;
    final minute = arrival.minute.toString().padLeft(2, '0');
    final suffix = arrival.hour < 12 ? 'AM' : 'PM';
    return 'ETA $hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final instruction = route == null
        ? null
        : instructionIndex < route!.instructions.length
        ? route!.instructions[instructionIndex].message
        : 'Continue to your destination';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xF20E1721),
        border: Border.all(color: const Color(0xFF2C3946)),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.navigation, color: Color(0xFF55E6B1), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loading
                      ? 'Finding the fastest route…'
                      : instruction ??
                            (waitingForDestination
                                ? 'اكتب وجهتك لعرض الطريق ووقت الوصول'
                                : error == null
                                ? 'Waiting for GPS location'
                                : 'Navigation unavailable'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF3F7FA),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: voiceEnabled
                    ? 'Mute voice guidance'
                    : 'Enable voice guidance',
                onPressed: () => onVoiceChanged(!voiceEnabled),
                icon: Icon(
                  voiceEnabled ? Icons.volume_up : Icons.volume_off,
                  color: const Color(0xFF55E6B1),
                ),
              ),
            ],
          ),
          if (route != null) ...[
            const Divider(height: 10, color: Color(0xFF2C3946)),
            Row(
              children: [
                _RouteStat(icon: Icons.schedule, label: _eta(remainingSeconds)),
                const SizedBox(width: 18),
                _RouteStat(
                  icon: Icons.route,
                  label: _distance(route!.distanceMeters),
                ),
                if (route!.trafficDelaySeconds > 0) ...[
                  const SizedBox(width: 18),
                  _RouteStat(
                    icon: Icons.traffic,
                    label: '+${_duration(route!.trafficDelaySeconds)} traffic',
                    color: AppColors.accent,
                  ),
                ],
              ],
            ),
          ],
          if (showRecalculate) ...[
            const SizedBox(height: 8),
            if (route != null)
              const Text(
                'أنت خارج الطريق منذ أكثر من دقيقتين.',
                style: TextStyle(color: Color(0xFFFFD18B), fontSize: 12),
              ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: loading ? null : onRecalculate,
                icon: const Icon(Icons.alt_route),
                label: Text(recalculateLabel),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF55E6B1),
                  side: const BorderSide(color: Color(0xFF55E6B1)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RouteStat extends StatelessWidget {
  const _RouteStat({
    required this.icon,
    required this.label,
    this.color = AppColors.muted,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 5),
      Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF3B2428),
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFFFFB8AE), fontSize: 12),
      ),
    ),
  );
}
