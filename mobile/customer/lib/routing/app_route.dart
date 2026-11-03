import 'package:flutter/material.dart';

/// Standard page route used for forward navigation across the app.
class TAMaterialRoute<T> extends PageRouteBuilder<T> {
  TAMaterialRoute({required this.builder, super.settings})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.05, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );

  final WidgetBuilder builder;
}
