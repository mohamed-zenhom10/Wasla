import 'package:shared_preferences/shared_preferences.dart';

class LanguageService {
  LanguageService._();

  static String current = 'en';

  static Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedLanguage = preferences.getString('profile_language');
      if (savedLanguage != null && savedLanguage.trim().isNotEmpty) {
        current = savedLanguage.trim();
      }
    } catch (_) {
      // Fall back to the default language when preferences are unavailable.
    }
  }

  static bool get isArabic {
    final normalized = current.trim().toLowerCase();
    return normalized.contains('عرب') || normalized.contains('arabic');
  }

  static String displayName(String? nameAr, String nameEn) {
    if (isArabic) {
      final arabic = nameAr?.trim();
      if (arabic != null && arabic.isNotEmpty) return arabic;
    }
    return nameEn;
  }
}
