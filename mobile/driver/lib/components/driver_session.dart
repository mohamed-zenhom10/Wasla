import 'package:driver/data/driver_api.dart';
import 'package:driver/screens/driver_auth_screen.dart';
import 'package:flutter/material.dart';

bool handleDriverSessionError(BuildContext context, Object error) {
  if (error is! DriverApiException || !error.requiresLogin) return false;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      builder: (_) => const DriverAuthScreen(startInLogin: true),
    ),
    (_) => false,
  );
  return true;
}
