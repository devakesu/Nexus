import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/encrypted_string.dart';

void main() {
  test('EncryptedString encrypts and decrypts correctly in memory', () async {
    const original = 'sensitive_api_key_123';
    final encrypted = await EncryptedString.create(original);

    // The plaintext should not be stored directly
    expect(encrypted.toString(), isNot(contains(original)));

    // Decryption works inside use() callback
    final decrypted = await encrypted.use((plainText) {
      expect(plainText, original);
      return plainText;
    });

    expect(decrypted, original);

    // Test wipe functionality
    expect(encrypted.isWiped, isFalse);
    encrypted.wipe();
    expect(encrypted.isWiped, isTrue);
    expect(() => encrypted.use((_) => null), throwsA(isA<StateError>()));
  });
}
