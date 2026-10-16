import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static const _completionKey = 'onboarding_completed';

  static Future<bool> isCompleted() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_completionKey) ?? false;
  }

  static Future<void> markCompleted() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_completionKey, true);
  }
}
