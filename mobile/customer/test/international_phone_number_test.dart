import 'package:flutter_test/flutter_test.dart';
import 'package:main/services/auth_service.dart';
import 'package:main/services/international_phone_number.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

void main() {
  test('normalizes Egyptian numbers with the selected country code', () {
    expect(
      InternationalPhoneNumber.toE164('01060975860', IsoCode.EG),
      '+201060975860',
    );
    expect(
      InternationalPhoneNumber.toE164('01001234567', IsoCode.EG),
      '+201001234567',
    );
  });

  test('validates against the selected international country', () {
    expect(
      InternationalPhoneNumber.parse('01060975860', IsoCode.EG),
      isNotNull,
    );
    expect(InternationalPhoneNumber.parse('123', IsoCode.EG), isNull);
    expect(
      InternationalPhoneNumber.toE164('+2001060975860', IsoCode.EG),
      isNull,
    );
    expect(
      InternationalPhoneNumber.toE164('02071234567', IsoCode.GB),
      '+442071234567',
    );
  });

  test(
    'auth session exposes the customer full name without a fallback name',
    () {
      const session = AuthSession(
        token: 'test-token',
        user: {'fullName': 'Customer Example'},
      );
      expect(session.fullName, 'Customer Example');

      const firstAndLast = AuthSession(
        token: 'test-token',
        user: {'firstName': 'Customer', 'lastName': 'Example'},
      );
      expect(firstAndLast.fullName, 'Customer Example');

      const noName = AuthSession(token: 'test-token', user: {});
      expect(noName.fullName, isNull);
    },
  );
}
