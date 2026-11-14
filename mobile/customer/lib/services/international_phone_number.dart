import 'package:phone_numbers_parser/phone_numbers_parser.dart';

class InternationalPhoneNumber {
  const InternationalPhoneNumber._();

  static PhoneNumber? parse(String nationalNumber, IsoCode country) {
    final input = nationalNumber.trim();
    if (input.isEmpty || !RegExp(r'^[0-9\s()-]+$').hasMatch(input)) {
      return null;
    }

    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;

    try {
      final phone = PhoneNumber.parse(digits, callerCountry: country);
      return phone.isValid() ? phone : null;
    } on PhoneNumberException {
      return null;
    }
  }

  static String? toE164(String nationalNumber, IsoCode country) =>
      parse(nationalNumber, country)?.international;

  static ({IsoCode country, String nationalNumber})? split(String value) {
    final input = value.trim();
    if (input.isEmpty) return null;

    try {
      final phone = PhoneNumber.parse(input);
      if (phone.isValid()) {
        return (country: phone.isoCode, nationalNumber: phone.nsn);
      }
    } on PhoneNumberException {
      // Fall through to country-specific parsing for national numbers.
    }

    for (final country in IsoCode.values) {
      final parsed = parse(input, country);
      if (parsed != null) {
        return (country: country, nationalNumber: parsed.nsn);
      }
    }
    return null;
  }
}
