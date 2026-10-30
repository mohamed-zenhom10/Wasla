import 'package:driver/components/driver_components.dart';
import 'package:driver/screens/incoming_request_screen.dart';
import 'package:driver/screens/requests_list_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool _isOnline = false;

  void _setOnline(bool value) {
    setState(() => _isOnline = value);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Availability is a local preview. No trips or requests are connected.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _HomeHeader(),
                    const SizedBox(height: 12),
                    const Text(
                      'Morning, Ahmed',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _AvailabilityCard(
                      isOnline: _isOnline,
                      onChanged: _setOnline,
                    ),
                    const SizedBox(height: 16),
                    _DriverStats(isOnline: _isOnline),
                    const SizedBox(height: 16),
                    const DriverMapPreview(),
                    if (_isOnline) ...[
                      const SizedBox(height: 16),
                      _RequestCard(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const IncomingRequestScreen(),
                          ),
                        ),
                      ),
                    ],
                    if (!_isOnline) ...[
                      const SizedBox(height: 16),
                      PrimaryButton(
                        label: 'Go online',
                        icon: Icons.power_settings_new,
                        onPressed: () => _setOnline(true),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            DriverNavigationBar(
              currentIndex: 0,
              onDestinationSelected: (index) {
                if (index == 0) return;
                if (index == 1) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RequestsListScreen(),
                    ),
                  );
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'This section does not have a supplied design yet.',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'W',
          style: TextStyle(
            color: AppColors.accent,
            fontSize: 34,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          'CAIRO OPERATIONS',
          style: TextStyle(color: AppColors.ink, fontSize: 10),
        ),
      ],
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({required this.isOnline, required this.onChanged});

  final bool isOnline;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isOnline ? 'You’re online' : 'You’re offline',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                value: isOnline,
                onChanged: onChanged,
                activeThumbColor: AppColors.accent,
                activeTrackColor: AppColors.ink,
                inactiveThumbColor: AppColors.white,
                inactiveTrackColor: AppColors.ink,
                trackOutlineColor: WidgetStatePropertyAll(
                  isOnline ? AppColors.accent : AppColors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            isOnline
                ? 'Ready for requests near Nasr City.'
                : 'Go online when you are ready to accept trips.',
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverStats extends StatelessWidget {
  const _DriverStats({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('EGP 1,240', 'Today’s net'),
      ('4', 'Trips'),
      (isOnline ? '3' : '0', 'Requests'),
    ];
    return Row(
      children: [
        for (var index = 0; index < stats.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stats[index].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stats[index].$2,
                    style: const TextStyle(color: AppColors.ink, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class DriverMapPreview extends StatelessWidget {
  const DriverMapPreview({super.key, this.height = 272});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            const Positioned.fill(child: CustomPaint(painter: _MapPainter())),
            const Align(
              alignment: Alignment(-0.05, -0.68),
              child: Text(
                'NASR CITY',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            const Align(
              alignment: Alignment(0.05, 0.48),
              child: Text('MAADI', style: TextStyle(fontSize: 11)),
            ),
            Align(
              alignment: Alignment(-0.08, -0.35),
              child: Transform.rotate(
                angle: -0.15,
                child: const Text(
                  'El Nasr Road',
                  style: TextStyle(fontSize: 10),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(10),
                child: IconButton(
                  tooltip: 'Recenter map',
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('The map location is a static preview.'),
                    ),
                  ),
                  icon: const Icon(Icons.my_location_outlined, size: 20),
                ),
              ),
            ),
            const Positioned(
              left: 28,
              bottom: 12,
              child: _MapLabel(text: 'Your location · Nasr City'),
            ),
            const Positioned(
              left: 70,
              top: 82,
              child: Icon(Icons.local_shipping_outlined, size: 22),
            ),
            const Positioned(
              right: 28,
              top: 126,
              child: Icon(Icons.local_shipping_outlined, size: 22),
            ),
            const Positioned(
              left: 116,
              bottom: 52,
              child: Icon(Icons.local_shipping_outlined, size: 22),
            ),
            const Positioned(
              right: 54,
              bottom: 60,
              child: Icon(Icons.location_on, color: AppColors.accent, size: 34),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapLabel extends StatelessWidget {
  const _MapLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontSize: 10)),
    );
  }
}

class _MapPainter extends CustomPainter {
  const _MapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = AppColors.surface;
    canvas.drawRect(Offset.zero & size, background);

    final roads = Paint()
      ..color = AppColors.white
      ..strokeWidth = 13
      ..style = PaintingStyle.stroke;
    final curvedRoad = Path()
      ..moveTo(size.width * 0.04, size.height * 0.03)
      ..cubicTo(
        size.width * 0.32,
        size.height * 0.28,
        size.width * 0.03,
        size.height * 0.57,
        size.width * 0.18,
        size.height * 1.08,
      );
    canvas.drawPath(curvedRoad, roads..strokeWidth = 25);

    final streetGrid = Paint()
      ..color = AppColors.white
      ..strokeWidth = 9
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width * 0.32, size.height * 0.42),
      Offset(size.width * 1.02, size.height * 0.62),
      streetGrid,
    );
    canvas.drawLine(
      Offset(size.width * 0.30, size.height * 0.64),
      Offset(size.width * 0.98, size.height * 0.85),
      streetGrid,
    );
    canvas.drawLine(
      Offset(size.width * 0.54, size.height * 0.32),
      Offset(size.width * 0.40, size.height * 1.04),
      streetGrid,
    );
    canvas.drawLine(
      Offset(size.width * 0.80, size.height * 0.36),
      Offset(size.width * 0.66, size.height * 1.04),
      streetGrid,
    );

    final route = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * 0.20, size.height * 0.33)
      ..lineTo(size.width * 0.48, size.height * 0.39)
      ..lineTo(size.width * 0.40, size.height * 0.56)
      ..lineTo(size.width * 0.82, size.height * 0.69)
      ..lineTo(size.width * 0.70, size.height * 0.85)
      ..lineTo(size.width * 0.89, size.height * 0.91);
    canvas.drawPath(path, route);

    final driverMarker = Paint()..color = AppColors.ink;
    canvas.drawCircle(
      Offset(size.width * 0.27, size.height * 0.35),
      15,
      driverMarker,
    );
    canvas.drawCircle(
      Offset(size.width * 0.27, size.height * 0.35),
      4,
      Paint()..color = AppColors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => false;
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.accent, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.local_shipping_outlined, size: 19),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Nearby · Nasr City → Maadi · EGP 432',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                'Quarter Truck · 12 items · 18 km · 55 min',
                style: TextStyle(fontSize: 12),
              ),
              SizedBox(height: 12),
              Text(
                'View request  ·  ›',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
