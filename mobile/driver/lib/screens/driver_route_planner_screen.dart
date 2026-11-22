import 'package:driver/components/driver_navigation_map.dart';
import 'package:flutter/material.dart';

class DriverRoutePlannerScreen extends StatelessWidget {
  const DriverRoutePlannerScreen({super.key});

  static const _background = Color(0xFF0B1118);
  static const _text = Color(0xFFF3F7FA);
  static const _muted = Color(0xFF9BA9B7);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _background,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 20, 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'رجوع',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, color: _text),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'خطة رحلتك',
                        style: TextStyle(
                          color: _text,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'اكتب وجهتك واتبع الطريق بالـ GPS',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.dark_mode, color: Color(0xFF55E6B1)),
              ],
            ),
          ),
          Expanded(
            child: DriverNavigationMap(
              trackCurrentLocation: true,
              showNavigationPanel: true,
              allowDestinationSearch: true,
              stageLabel: 'مسار مباشر',
            ),
          ),
        ],
      ),
    ),
  );
}
