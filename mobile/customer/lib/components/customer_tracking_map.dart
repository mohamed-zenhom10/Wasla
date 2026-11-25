import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:main/models/shipment.dart';
import 'package:main/services/tomtom_routing_service.dart';

class CustomerTrackingMap extends StatefulWidget {
  const CustomerTrackingMap({
    super.key,
    required this.shipment,
    this.tracking,
    this.height = 280,
  });

  final Shipment shipment;
  final ShipmentTracking? tracking;
  final double height;

  @override
  State<CustomerTrackingMap> createState() => _CustomerTrackingMapState();
}

class _CustomerTrackingMapState extends State<CustomerTrackingMap> {
  static const _fallbackCenter = LatLng(30.0444, 31.2357);
  static const _night = Color(0xFF0E1721);
  static const _accent = Color(0xFF55E6B1);
  static const _pickupColor = Color(0xFF1F8A70);
  static const _deliveryColor = Color(0xFFFFC857);

  final _mapController = MapController();
  final _routing = TomTomRoutingService();
  TomTomRoute? _route;
  String? _routeError;
  bool _loadingRoute = false;
  bool _mapReady = false;
  bool _followDriver = true;
  bool _tileError = false;
  String? _requestedStage;

  ShipmentLocation? get _pickup => widget.shipment.pickup;
  ShipmentLocation? get _dropoff => widget.shipment.dropoff;
  ShipmentLocation? get _driver => widget.tracking?.driverLocation;

  String get _stage {
    final nextStop = widget.tracking?.nextStop;
    if (nextStop == 'pickup' || nextStop == 'dropoff') return nextStop!;
    final status = widget.tracking?.tripStatus ?? widget.shipment.trip?.status;
    if (status == 'assigned' ||
        status == 'heading_to_pickup' ||
        status == 'arrived_at_pickup') {
      return 'pickup';
    }
    if (status == 'loaded' ||
        status == 'heading_to_dropoff' ||
        status == 'arrived_at_dropoff') {
      return 'dropoff';
    }
    return 'shipment';
  }

  LatLng? get _driverPoint {
    final location = _driver;
    if (location == null) return null;
    return LatLng(location.latitude, location.longitude);
  }

  LatLng? get _routeStart {
    if (_stage == 'shipment') {
      final pickup = _pickup;
      return pickup == null ? null : LatLng(pickup.latitude, pickup.longitude);
    }
    return _driverPoint;
  }

  LatLng? get _routeEnd {
    final location = _stage == 'dropoff' ? _dropoff : _pickup;
    if (_stage == 'shipment') {
      final dropoff = _dropoff;
      return dropoff == null
          ? null
          : LatLng(dropoff.latitude, dropoff.longitude);
    }
    return location == null
        ? null
        : LatLng(location.latitude, location.longitude);
  }

  String get _stageLabel => switch (_stage) {
    'pickup' => 'Driver heading to pickup',
    'dropoff' => 'Shipment on the way',
    _ => 'Shipment route',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoute());
  }

  @override
  void didUpdateWidget(covariant CustomerTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldStage = _stageFor(oldWidget);
    final locationAppeared =
        oldWidget.tracking?.driverLocation == null && _driver != null;
    if (oldStage != _stage) {
      _route = null;
      _routeError = null;
      _requestedStage = null;
      _loadingRoute = false;
    }
    if (oldStage != _stage || locationAppeared) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoute());
    }
    if (_followDriver && _mapReady && _driverPoint != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _followDriver) {
          _mapController.move(_driverPoint!, 15);
        }
      });
    }
  }

  String _stageFor(CustomerTrackingMap page) {
    final nextStop = page.tracking?.nextStop;
    if (nextStop == 'pickup' || nextStop == 'dropoff') return nextStop!;
    final status = page.tracking?.tripStatus ?? page.shipment.trip?.status;
    if (status == 'assigned' ||
        status == 'heading_to_pickup' ||
        status == 'arrived_at_pickup') {
      return 'pickup';
    }
    if (status == 'loaded' ||
        status == 'heading_to_dropoff' ||
        status == 'arrived_at_dropoff') {
      return 'dropoff';
    }
    return 'shipment';
  }

  Future<void> _loadRoute({bool retry = false}) async {
    final stage = _stage;
    final start = _routeStart;
    final end = _routeEnd;
    if (start == null || end == null) return;
    if (!retry && _requestedStage == stage) return;
    _requestedStage = stage;
    setState(() {
      _loadingRoute = true;
      _routeError = null;
      _route = null;
    });
    try {
      final route = await _routing.calculateRoute(
        start: start,
        destination: end,
      );
      if (!mounted || stage != _stage) return;
      setState(() => _route = route);
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitRoute());
    } catch (error) {
      if (!mounted || stage != _stage) return;
      setState(() => _routeError = error.toString());
    } finally {
      if (mounted && stage == _stage) {
        setState(() => _loadingRoute = false);
      }
    }
  }

  void _fitRoute() {
    if (!_mapReady || _route == null || !mounted) return;
    final points = [..._route!.points, ?_driverPoint];
    if (points.length < 2) return;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(38),
      ),
    );
  }

  void _onTileError(Object error, StackTrace? stackTrace) {
    if (_tileError || !mounted) return;
    setState(() => _tileError = true);
  }

  List<Marker> get _markers {
    final markers = <Marker>[];
    final driver = _driverPoint;
    if (driver != null) {
      markers.add(
        Marker(
          point: driver,
          width: 44,
          height: 44,
          child: const _LocationDot(),
        ),
      );
    }
    final pickup = _pickup;
    if (pickup != null) {
      markers.add(
        Marker(
          point: LatLng(pickup.latitude, pickup.longitude),
          width: 48,
          height: 58,
          alignment: Alignment.topCenter,
          child: const _PlacePin(icon: Icons.storefront, color: _pickupColor),
        ),
      );
    }
    final dropoff = _dropoff;
    if (dropoff != null) {
      markers.add(
        Marker(
          point: LatLng(dropoff.latitude, dropoff.longitude),
          width: 48,
          height: 58,
          alignment: Alignment.topCenter,
          child: const _PlacePin(icon: Icons.flag, color: _deliveryColor),
        ),
      );
    }
    return markers;
  }

  String _distance(int meters) =>
      meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '$meters m';

  String _duration(int seconds) {
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${minutes % 60} min';
  }

  String _eta(int durationSeconds) {
    final arrival = DateTime.now().add(Duration(seconds: durationSeconds));
    final hour = arrival.hour % 12 == 0 ? 12 : arrival.hour % 12;
    final minute = arrival.minute.toString().padLeft(2, '0');
    final suffix = arrival.hour < 12 ? 'AM' : 'PM';
    return 'ETA $hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final pickup = _pickup;
    final dropoff = _dropoff;
    final points = [
      ?_driverPoint,
      ?(pickup == null ? null : LatLng(pickup.latitude, pickup.longitude)),
      ?(dropoff == null ? null : LatLng(dropoff.latitude, dropoff.longitude)),
    ];
    final center =
        _driverPoint ?? (points.isNotEmpty ? points.first : _fallbackCenter);

    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 13,
                minZoom: 3,
                maxZoom: 19,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
                onMapReady: () {
                  _mapReady = true;
                  _fitRoute();
                },
                onPositionChanged: (_, hasGesture) {
                  if (hasGesture) _followDriver = false;
                },
              ),
              children: [
                if (TomTomRoutingService.apiKey.isNotEmpty)
                  TileLayer(
                    urlTemplate:
                        'https://api.tomtom.com/map/1/tile/basic/night/'
                        '{z}/{x}/{y}.png?view=Unified&tileSize=512&key={key}',
                    additionalOptions: {'key': TomTomRoutingService.apiKey},
                    tileDimension: 512,
                    zoomOffset: -1,
                    maxNativeZoom: 19,
                    keepBuffer: 2,
                    panBuffer: 0,
                    userAgentPackageName: 'com.wasla.customer',
                    errorTileCallback: (_, error, stackTrace) =>
                        _onTileError(error, stackTrace),
                  ),
                if (_route != null && TomTomRoutingService.apiKey.isNotEmpty)
                  Opacity(
                    opacity: 0.58,
                    child: TileLayer(
                      urlTemplate:
                          'https://api.tomtom.com/traffic/map/4/tile/flow/relative/'
                          '{z}/{x}/{y}.png?tileSize=512&key={key}',
                      additionalOptions: {'key': TomTomRoutingService.apiKey},
                      tileDimension: 512,
                      zoomOffset: -1,
                      maxNativeZoom: 18,
                      keepBuffer: 2,
                      panBuffer: 0,
                      userAgentPackageName: 'com.wasla.customer',
                      errorTileCallback: (_, error, stackTrace) =>
                          _onTileError(error, stackTrace),
                    ),
                  ),
                if (_route != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _route!.points,
                        color: _accent,
                        strokeWidth: 8,
                        borderStrokeWidth: 2.5,
                        borderColor: _night,
                      ),
                    ],
                  ),
                MarkerLayer(markers: _markers),
              ],
            ),
            Positioned(
              top: 14,
              left: 14,
              child: _MapBadge(icon: Icons.route, label: _stageLabel),
            ),
            Positioned(
              top: 14,
              right: 14,
              child: _MapControl(
                tooltip: 'Center on driver',
                onPressed: _driverPoint == null ? null : _centerOnDriver,
              ),
            ),
            if (_route != null)
              const Positioned(
                top: 60,
                left: 14,
                child: _MapBadge(
                  icon: Icons.traffic,
                  label: 'Live traffic',
                  compact: true,
                ),
              ),
            const Positioned(
              left: 14,
              bottom: 105,
              child: Text(
                '© TomTom',
                style: TextStyle(
                  color: Color(0xFFF3F7FA),
                  fontSize: 10,
                  shadows: [Shadow(color: Colors.black, blurRadius: 5)],
                ),
              ),
            ),
            if (_loadingRoute)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 3),
              ),
            if (!_loadingRoute &&
                _routeError == null &&
                _stage != 'shipment' &&
                _driverPoint == null)
              const Positioned(
                top: 60,
                left: 14,
                right: 14,
                child: _MapInfoBadge(
                  icon: Icons.location_searching,
                  message: 'Waiting for driver location',
                ),
              ),
            if (_routeError != null ||
                _tileError ||
                TomTomRoutingService.apiKey.isEmpty)
              Positioned(
                top: 60,
                left: 14,
                right: 14,
                child: _MapErrorBanner(
                  message:
                      _routeError ??
                      (_tileError
                          ? 'TomTom map tiles are unavailable. Check your connection.'
                          : 'TomTom API key is required to load the map.'),
                  onRetry: _routeError == null
                      ? null
                      : () => _loadRoute(retry: true),
                ),
              ),
            if (_route != null)
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: _RouteSummary(
                  route: _route!,
                  distance: _distance,
                  duration: _duration,
                  eta: _eta,
                  stageLabel: _stageLabel,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _centerOnDriver() {
    final driver = _driverPoint;
    if (driver == null) return;
    _followDriver = true;
    _mapController.move(driver, 15);
  }
}

class CustomerMapPreview extends StatefulWidget {
  const CustomerMapPreview({
    super.key,
    this.pickup,
    this.destination,
    this.height = 250,
  });

  final LatLng? pickup;
  final LatLng? destination;
  final double height;

  @override
  State<CustomerMapPreview> createState() => _CustomerMapPreviewState();
}

class _CustomerMapPreviewState extends State<CustomerMapPreview> {
  static const _fallbackCenter = LatLng(30.0444, 31.2357);
  static const _night = Color(0xFF0E1721);
  static const _accent = Color(0xFF55E6B1);
  static const _pickupColor = Color(0xFF1F8A70);
  static const _destinationColor = Color(0xFFFFC857);

  final _mapController = MapController();
  final _routing = TomTomRoutingService();
  TomTomRoute? _route;
  String? _routeError;
  bool _loadingRoute = false;
  bool _mapReady = false;
  bool _tileError = false;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoute());
  }

  @override
  void didUpdateWidget(covariant CustomerMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pickup != widget.pickup ||
        oldWidget.destination != widget.destination) {
      _requestGeneration++;
      setState(() {
        _route = null;
        _routeError = null;
        _loadingRoute = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitSelection();
        _loadRoute();
      });
    }
  }

  Future<void> _loadRoute() async {
    final pickup = widget.pickup;
    final destination = widget.destination;
    if (pickup == null || destination == null) return;

    final generation = ++_requestGeneration;
    setState(() {
      _loadingRoute = true;
      _routeError = null;
    });
    try {
      final route = await _routing.calculateRoute(
        start: pickup,
        destination: destination,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _route = route);
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitSelection());
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _routeError = error.toString());
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loadingRoute = false);
      }
    }
  }

  void _fitSelection() {
    if (!_mapReady || !mounted) return;
    final points = _route?.points ?? [?widget.pickup, ?widget.destination];
    if (points.length > 1) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(34),
        ),
      );
    } else if (points.length == 1) {
      _mapController.move(points.single, 14);
    }
  }

  void _centerMap() {
    if (_route != null || widget.pickup != null || widget.destination != null) {
      _fitSelection();
    } else {
      _mapController.move(_fallbackCenter, 12);
    }
  }

  void _onTileError() {
    if (_tileError || !mounted) return;
    setState(() => _tileError = true);
  }

  String _distance(int meters) =>
      meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '$meters m';

  String _duration(int seconds) {
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${minutes % 60} min';
  }

  String _eta(int durationSeconds) {
    final arrival = DateTime.now().add(Duration(seconds: durationSeconds));
    final hour = arrival.hour % 12 == 0 ? 12 : arrival.hour % 12;
    final minute = arrival.minute.toString().padLeft(2, '0');
    final suffix = arrival.hour < 12 ? 'AM' : 'PM';
    return 'ETA $hour:$minute $suffix';
  }

  List<Marker> get _markers => [
    if (widget.pickup case final pickup?)
      Marker(
        point: pickup,
        width: 48,
        height: 58,
        alignment: Alignment.topCenter,
        child: const Tooltip(
          message: 'Pickup',
          child: _PlacePin(icon: Icons.storefront, color: _pickupColor),
        ),
      ),
    if (widget.destination case final destination?)
      Marker(
        point: destination,
        width: 48,
        height: 58,
        alignment: Alignment.topCenter,
        child: const Tooltip(
          message: 'Destination',
          child: _PlacePin(icon: Icons.flag, color: _destinationColor),
        ),
      ),
  ];

  @override
  void dispose() {
    _requestGeneration++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter:
                    widget.pickup ?? widget.destination ?? _fallbackCenter,
                initialZoom: 12,
                minZoom: 3,
                maxZoom: 19,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
                onMapReady: () {
                  _mapReady = true;
                  _fitSelection();
                },
              ),
              children: [
                if (TomTomRoutingService.apiKey.isNotEmpty)
                  TileLayer(
                    urlTemplate:
                        'https://api.tomtom.com/map/1/tile/basic/night/'
                        '{z}/{x}/{y}.png?view=Unified&tileSize=512&key={key}',
                    additionalOptions: {'key': TomTomRoutingService.apiKey},
                    tileDimension: 512,
                    zoomOffset: -1,
                    maxNativeZoom: 19,
                    keepBuffer: 2,
                    panBuffer: 0,
                    userAgentPackageName: 'com.wasla.customer',
                    errorTileCallback: (_, _, _) => _onTileError(),
                  ),
                if (_route != null && TomTomRoutingService.apiKey.isNotEmpty)
                  Opacity(
                    opacity: 0.58,
                    child: TileLayer(
                      urlTemplate:
                          'https://api.tomtom.com/traffic/map/4/tile/flow/relative/'
                          '{z}/{x}/{y}.png?tileSize=512&key={key}',
                      additionalOptions: {'key': TomTomRoutingService.apiKey},
                      tileDimension: 512,
                      zoomOffset: -1,
                      maxNativeZoom: 18,
                      keepBuffer: 2,
                      panBuffer: 0,
                      userAgentPackageName: 'com.wasla.customer',
                      errorTileCallback: (_, _, _) => _onTileError(),
                    ),
                  ),
                if (_route case final route?)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: route.points,
                        color: _accent,
                        strokeWidth: 8,
                        borderStrokeWidth: 2.5,
                        borderColor: _night,
                      ),
                    ],
                  ),
                MarkerLayer(markers: _markers),
              ],
            ),
          ),
          const Positioned(
            top: 14,
            left: 14,
            child: _MapBadge(icon: Icons.route, label: 'TomTom map'),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: _MapControl(tooltip: 'Center map', onPressed: _centerMap),
          ),
          if (_route != null)
            const Positioned(
              top: 60,
              left: 14,
              child: _MapBadge(
                icon: Icons.traffic,
                label: 'Live traffic',
                compact: true,
              ),
            ),
          if (_loadingRoute)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 3),
            ),
          if (_routeError != null ||
              _tileError ||
              TomTomRoutingService.apiKey.isEmpty)
            Positioned(
              top: 60,
              left: 14,
              right: 14,
              child: _MapErrorBanner(
                message:
                    _routeError ??
                    (_tileError
                        ? 'TomTom map tiles are unavailable. Check your connection.'
                        : 'TomTom API key is required to load the map.'),
                onRetry: _routeError == null ? null : () => _loadRoute(),
              ),
            ),
          if (widget.pickup == null || widget.destination == null)
            const Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: _MapInfoBadge(
                icon: Icons.pin_drop_outlined,
                message: 'Choose pickup and destination to preview your route',
              ),
            ),
          if (_route != null)
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: _RouteSummary(
                route: _route!,
                distance: _distance,
                duration: _duration,
                eta: _eta,
                stageLabel: 'Route estimate',
              ),
            ),
          Positioned(
            left: 14,
            bottom: _route == null ? 60 : 105,
            child: const Text(
              '© TomTom',
              style: TextStyle(
                color: Color(0xFFF3F7FA),
                fontSize: 10,
                shadows: [Shadow(color: Colors.black, blurRadius: 5)],
              ),
            ),
          ),
        ],
      ),
    ),
  );
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
  const _MapControl({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF111B25),
    shape: const CircleBorder(),
    elevation: 3,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: const Icon(Icons.my_location, color: Color(0xFF55E6B1)),
    ),
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

class _MapInfoBadge extends StatelessWidget {
  const _MapInfoBadge({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xF0101820),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Icon(icon, size: 17, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MapErrorBanner extends StatelessWidget {
  const _MapErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xF0101820),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.redAccent),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.route_outlined, color: Colors.redAccent, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({
    required this.route,
    required this.distance,
    required this.duration,
    required this.eta,
    required this.stageLabel,
  });

  final TomTomRoute route;
  final String Function(int) distance;
  final String Function(int) duration;
  final String Function(int) eta;
  final String stageLabel;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xF20E1721),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF2C3946)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.navigation, color: Color(0xFF55E6B1), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stageLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF3F7FA),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.traffic, color: Color(0xFF55E6B1), size: 16),
              const SizedBox(width: 5),
              const Text(
                'Live',
                style: TextStyle(
                  color: Color(0xFF55E6B1),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Divider(height: 12, color: Color(0xFF2C3946)),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _RouteStat(
                icon: Icons.schedule,
                label: eta(route.travelTimeSeconds),
              ),
              _RouteStat(
                icon: Icons.route,
                label: distance(route.distanceMeters),
              ),
              if (route.trafficDelaySeconds > 0)
                _RouteStat(
                  icon: Icons.traffic,
                  label: '+${duration(route.trafficDelaySeconds)} traffic',
                  color: const Color(0xFFFFC857),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _RouteStat extends StatelessWidget {
  const _RouteStat({
    required this.icon,
    required this.label,
    this.color = const Color(0xFFB7C4D0),
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
