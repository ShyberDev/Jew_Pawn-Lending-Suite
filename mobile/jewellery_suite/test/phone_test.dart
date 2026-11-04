import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/util/account.dart';
import 'package:jewellery_suite/util/phone.dart';

/// #070 — an Indian mobile is either 10 digits or the same number with the
/// +91 country code. Dialling, SMS and WhatsApp must all agree on it.
void main() {
  group('Phone.national', () {
    test('a plain 10-digit mobile is kept as-is', () {
      expect(Phone.national('9876543210'), '9876543210');
      expect(Phone.isValid('9876543210'), isTrue);
    });

    test('+91, 91, 0091 and a trunk 0 all reduce to the same 10 digits', () {
      const expected = '9876543210';
      expect(Phone.national('+91 98765 43210'), expected);
      expect(Phone.national('+919876543210'), expected);
      expect(Phone.national('919876543210'), expected);
      expect(Phone.national('0091 98765 43210'), expected);
      expect(Phone.national('098765 43210'), expected);
      expect(Phone.national('+91-98765-43210'), expected);
      expect(Phone.national('(0) 98765 43210'), expected);
    });

    test('anything that is not a mobile is refused', () {
      expect(Phone.national(''), '');
      expect(Phone.national('98765'), ''); // too short
      expect(Phone.national('98765432101'), ''); // 11 digits, no trunk 0
      expect(Phone.national('1234567890'), ''); // landline / starts 1
      expect(Phone.national('5876543210'), ''); // starts 5
      expect(Phone.national('0452 2345678'), ''); // landline with STD code
      expect(Phone.national('call me'), '');
      expect(Phone.national('+1 415 555 0100'), '');
      expect(Phone.invalidMessage, contains('10-digit'));
    });

    test('pretty and e164 give one agreed spelling', () {
      expect(Phone.e164('9876543210'), '+919876543210');
      expect(Phone.e164('not a number'), '');
      expect(Phone.pretty('+91 98765 43210'), '+91 98765 43210');
      expect(Phone.pretty('nothing'), 'nothing');
    });

    test('a field is optional unless required', () {
      expect(Phone.validationError(''), isNull);
      expect(Phone.validationError(null), isNull);
      expect(Phone.validationError('', required: true), 'Required');
      expect(Phone.validationError('9876543210'), isNull);
      expect(Phone.validationError('98765'), Phone.invalidMessage);
    });
  });

  group('opening the phone', () {
    test('tel, SMS and WhatsApp all carry the country code', () {
      final tel = Phone.tel('98765 43210')!;
      expect(tel.scheme, 'tel');
      expect(tel.path, '+919876543210');

      final sms = Phone.sms('+91 98765 43210', body: 'Namaste 🙏')!;
      expect(sms.scheme, 'sms');
      expect(sms.path, '+919876543210');
      expect(sms.queryParameters['body'], 'Namaste 🙏');

      expect(Phone.sms('9876543210')!.queryParameters, isEmpty);

      final wa = Phone.whatsapp('9876543210', text: 'Hi & bye');
      expect(wa, isNotNull);
      expect(wa!.host, 'wa.me');
      expect(wa.pathSegments.single, '919876543210');
      expect(wa.queryParameters['text'], 'Hi & bye');
    });

    test('a number that cannot be dialled yields no link', () {
      expect(Phone.tel('123'), isNull);
      expect(Phone.sms('landline'), isNull);
      expect(Phone.whatsapp('+1 415 555 0100', text: 'x'), isNull);
    });
  });

  group('login identifier', () {
    test('uses the same Indian-mobile rule', () {
      expect(LocalAccount.isMobile('+91 98765 43210'), isTrue);
      expect(LocalAccount.isMobile('1234567890'), isFalse);
      expect(LocalAccount.isValidIdentifier('shop@gmail.com'), isTrue);
      expect(LocalAccount.isValidIdentifier('shop at gmail'), isFalse);
    });

    test('one account for the same number typed either way', () {
      expect(LocalAccount.normalizeIdentifier('+91 98765 43210'),
          LocalAccount.normalizeIdentifier('9876543210'));
      expect(LocalAccount.normalizeIdentifier('Shop@Gmail.com'), 'shop@gmail.com');
      // Older accounts keep their last ten digits so nobody is locked out.
      expect(LocalAccount.normalizeIdentifier('0123456789'), '0123456789');
    });
  });
}
