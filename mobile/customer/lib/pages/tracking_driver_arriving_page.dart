import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/pages/tracking_in_transit_page.dart';
import 'package:main/routing/app_route.dart';
import 'package:main/services/mock_data.dart';
import 'package:main/theme/app_theme.dart';

class TrackingDriverArrivingPage extends StatefulWidget {
  const TrackingDriverArrivingPage({super.key});

  @override
  State<TrackingDriverArrivingPage> createState() =>
      _TrackingDriverArrivingPageState();
}

class _TrackingDriverArrivingPageState extends State<TrackingDriverArrivingPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  const SizedBox(height: 16),
                  _buildMapCard(),
                  const SizedBox(height: 12),
                  _buildStatusCard(),
                  const SizedBox(height: 12),
                  _buildEtaCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back, size: 24),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const Spacer(),
          Text('WASLA', style: AppTypography.eyebrow),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildMapCard() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _MapPainter())),
          const Align(
            alignment: Alignment(-0.3, -0.4),
            child: Text('NASR CITY', style: TextStyle(fontSize: 10)),
          ),
          const Align(
            alignment: Alignment(0, 0.6),
            child: Text('MAADI', style: TextStyle(fontSize: 10)),
          ),
          Align(
            alignment: Alignment(-0.2, -0.1),
            child: Icon(Icons.local_shipping, color: AppColors.accent, size: 28),
          ),
          Align(
            alignment: Alignment(0.4, 0.3),
            child: Icon(Icons.location_on, color: AppColors.darkGreen, size: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            'Driver is arriving',
            style: AppTypography.headingSm,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            TrackingMock.driverName,
            style: AppTypography.bodyMd,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEtaCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.darkGreen, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.access_time, color: AppColors.darkGreen, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ETA', style: AppTypography.labelSm),
                Text('${TrackingMock.eta} minutes', style: AppTypography.bodyMd),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: WaslaButton(
        text: 'Track live',
        variant: WaslaButtonVariant.primary,
        onPressed: () => Navigator.of(context).push(
          TAMaterialRoute<void>(
            builder: (_) => const TrackingInTransitPage(),
          ),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  const _MapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = AppColors.light;
    canvas.drawRect(Offset.zero & size, background);

    final roadPaint = Paint()
      ..color = AppColors.white
      ..strokeWidth = 20
      ..style = PaintingStyle.stroke;
    final road = Path()
      ..moveTo(size.width * .1, -10)
      ..cubicTo(
        size.width * .4,
        size.height * .3,
        size.width * .1,
        size.height * .6,
        size.width * .05,
        size.height + 10,
      );
    canvas.drawPath(road, roadPaint);

    final routePaint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final route = Path()
      ..moveTo(size.width * .3, size.height * .5)
      ..lineTo(size.width * .5, size.height * .55)
      ..lineTo(size.width * .8, size.height * .7);
    canvas.drawPath(route, routePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}