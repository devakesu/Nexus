import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/safety_contacts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('Phase 98 - Safety Contacts and Storage Mega Tests', () {
    test('SafetyContact model json serialization and persistence', () async {
      final contact = SafetyContact(name: 'Bob', phone: '+14155551234');
      expect(contact.name, 'Bob');
      expect(contact.phone, '+14155551234');

      final json = contact.toJson();
      final fromJson = SafetyContact.fromJson(json);
      expect(fromJson.name, 'Bob');
      expect(fromJson.phone, '+14155551234');

      final list = [contact];
      await saveSafetyContacts(list);
      final loaded = await loadSafetyContacts();
      expect(loaded.length, 1);
      expect(loaded.first.name, 'Bob');
    });
  });
}
