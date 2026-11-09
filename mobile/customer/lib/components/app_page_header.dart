import 'package:flutter/material.dart';
import 'package:main/theme/app_theme.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/icon.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'Wasla',
    );
  }
}

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppLogo(size: 38),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTypography.headingSm.copyWith(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ],
    );
  }
}
