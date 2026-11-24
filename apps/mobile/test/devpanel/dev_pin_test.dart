import 'package:flutter_test/flutter_test.dart';
import 'package:khazain_al_huda/devpanel/pin.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late DevPinService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    service = DevPinService(prefs);
  });

  test('the pin is never stored in plaintext', () {
    service.setPin('1234', '1234');

    final raw = prefs.getString(DevPinService.storageKey);
    expect(raw, isNotNull);
    expect(raw, isNot(contains('1234')));
    expect(raw, contains('salt'));
    expect(raw, contains('hash'));
  });

  test('a matching pin unlocks and a wrong pin does not', () {
    service.setPin('1234', '1234');
    expect(service.verify('1234'), isTrue);
    expect(service.verify('4321'), isFalse);
    expect(service.verify('12'), isFalse);
  });

  test('the confirmation must match', () {
    expect(service.setPin('1234', '4321'), isFalse);
    expect(service.hasPin, isFalse);
  });

  test('a pin must be four digits', () {
    expect(service.setPin('123', '123'), isFalse);
    expect(service.setPin('12345', '12345'), isFalse);
  });

  test('the panel locks itself after five idle minutes', () {
    service.setPin('1234', '1234');
    expect(service.isIdleLocked, isFalse);

    prefs.setString(
      '${DevPinService.storageKey}.lastUnlock',
      (DateTime.now().millisecondsSinceEpoch -
              const Duration(minutes: 6).inMilliseconds)
          .toString(),
    );
    expect(service.isIdleLocked, isTrue);

    service.lock();
    expect(service.lastUnlockMillis, isNull);
    expect(service.isIdleLocked, isTrue);
  });

  test('two pins with the same value produce different stored digests',
      () async {
    service.setPin('1234', '1234');
    final first = prefs.getString(DevPinService.storageKey);

    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    service = DevPinService(prefs);
    service.setPin('1234', '1234');
    final second = prefs.getString(DevPinService.storageKey);

    expect(first, isNot(second));
    expect(service.verify('1234'), isTrue);
  });
}
