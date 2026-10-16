import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/screens/login_screen.dart';
import 'package:main/theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.isPreview = false});

  final bool isPreview;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _pickupController = TextEditingController();
  final _destinationController = TextEditingController();
  int _selectedTab = 0;

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _requestMove() {
    if (_pickupController.text.trim().isEmpty ||
        _destinationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a pickup and destination first.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Trip requests will be available when the service is connected.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'W',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 36,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Text(
                    'CAIRO, EGYPT',
                    style: TextStyle(color: AppColors.darkGreen, fontSize: 10),
                  ),
                ],
              ),
              if (widget.isPreview) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.light,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Preview only - not signed in',
                    style: TextStyle(color: AppColors.darkGreen, fontSize: 11),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Morning, Mariam',
                style: TextStyle(
                  color: AppColors.darkGreen,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              const _MapPreview(),
              const SizedBox(height: 20),
              const Text(
                'Where are you moving\nsomething?',
                style: TextStyle(
                  color: AppColors.darkGreen,
                  fontSize: 20,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.light,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _LocationInput(
                      controller: _pickupController,
                      icon: Icons.radio_button_checked,
                      hint: 'Pickup location',
                    ),
                    const Divider(height: 1),
                    _LocationInput(
                      controller: _destinationController,
                      icon: Icons.location_on_outlined,
                      hint: 'Where to?',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              MainButton(
                text: 'Move something',
                onPressed: _requestMove,
                borderRadius: 8,
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.light,
                  border: Border.all(color: AppColors.accent, width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Not sure which truck you need?',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Let Wasla choose it for you.',
                      style: TextStyle(fontSize: 12),
                    ),
                    TextButton.icon(
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Cargo estimates will be available soon.',
                              ),
                            ),
                          ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.darkGreen,
                        padding: const EdgeInsets.only(top: 8),
                      ),
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text(
                        'Estimate my cargo',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: _selectedTab,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppColors.accent,
          unselectedItemColor: AppColors.darkGreen,
          selectedFontSize: 10,
          unselectedFontSize: 10,
          onTap: (index) {
            setState(() => _selectedTab = index);
            if (index == 4 && widget.isPreview) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
              );
              return;
            }
            if (index != 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${_tabNames[index]} is not connected yet.'),
                ),
              );
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.alt_route),
              label: 'Trips',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              label: 'Messages',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              label: 'Wallet',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

const _tabNames = ['Home', 'Trips', 'Messages', 'Wallet', 'Profile'];

class _LocationInput extends StatelessWidget {
  const _LocationInput({
    required this.controller,
    required this.icon,
    required this.hint,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.darkGreen, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            style: const TextStyle(color: AppColors.darkGreen, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              hintStyle: const TextStyle(color: AppColors.darkGreen),
            ),
          ),
        ),
      ],
    );
  }
}

class _MapPreview extends StatelessWidget {
  const _MapPreview();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 192,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            const Positioned.fill(child: CustomPaint(painter: _MapPainter())),
            const Align(
              alignment: Alignment(-0.15, -0.52),
              child: Text('NASR CITY'),
            ),
            const Align(alignment: Alignment(0, 0.54), child: Text('MAADI')),
            const Align(
              alignment: Alignment(-0.12, -0.05),
              child: Text('El Nasr Road', style: TextStyle(fontSize: 10)),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(10),
                child: IconButton(
                  tooltip: 'Recenter map',
                  onPressed: () {},
                  icon: const Icon(Icons.my_location_outlined, size: 20),
                ),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Closest truck · 8 min away',
                  style: TextStyle(fontSize: 10),
                ),
              ),
            ),
            const Align(
              alignment: Alignment(-0.48, -0.15),
              child: Icon(Icons.local_shipping_outlined, size: 22),
            ),
            const Align(
              alignment: Alignment(0.86, 0.5),
              child: Icon(Icons.local_shipping_outlined, size: 22),
            ),
            const Align(
              alignment: Alignment(0.62, 0.12),
              child: Icon(Icons.location_on, color: AppColors.accent, size: 32),
            ),
          ],
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
      ..strokeWidth = 25
      ..style = PaintingStyle.stroke;
    final road = Path()
      ..moveTo(size.width * .08, -10)
      ..cubicTo(
        size.width * .36,
        size.height * .28,
        size.width * .08,
        size.height * .62,
        size.width * .02,
        size.height + 10,
      );
    canvas.drawPath(road, roadPaint);

    final crossRoad = Paint()
      ..color = AppColors.white
      ..strokeWidth = 18
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 4; i++) {
      final x = size.width * (.35 + i * .19);
      canvas.drawLine(Offset(x, 0), Offset(x - 30, size.height), crossRoad);
    }

    final routePaint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final route = Path()
      ..moveTo(size.width * .2, size.height * .45)
      ..lineTo(size.width * .4, size.height * .48)
      ..lineTo(size.width * .49, size.height * .57)
      ..lineTo(size.width * .42, size.height * .69)
      ..lineTo(size.width * .88, size.height * .78);
    canvas.drawPath(route, routePaint);

    final pickup = Paint()..color = AppColors.darkGreen;
    canvas.drawCircle(Offset(size.width * .28, size.height * .48), 15, pickup);
    final center = Paint()..color = AppColors.white;
    canvas.drawCircle(Offset(size.width * .28, size.height * .48), 4, center);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
