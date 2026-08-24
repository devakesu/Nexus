import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/signal/media_crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'MediaCrypto encrypts video bytes to ciphertext and decrypts accurately',
    () async {
      final plaintextBytes = Uint8List.fromList(
        List.generate(1024, (i) => i % 256),
      );

      final encrypted = await MediaCrypto.instance.encrypt(plaintextBytes);
      expect(encrypted.ciphertext, isNot(equals(plaintextBytes)));
      expect(encrypted.mediaKeyBase64.isNotEmpty, isTrue);

      // Decrypt
      final decrypted = await MediaCrypto.instance.decrypt(
        encrypted.ciphertext,
        encrypted.mediaKeyBase64,
      );
      expect(decrypted, equals(plaintextBytes));
    },
  );

  test(
    'Encrypted video segments can be written as .enc and original deleted',
    () async {
      final tempDir = Directory.systemTemp;
      final rawFile = File(
        '${tempDir.path}/test_raw_video_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );
      await rawFile.writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8]);
      expect(rawFile.existsSync(), isTrue);

      // Immediate on-disk encryption pattern
      final bytes = await rawFile.readAsBytes();
      final encrypted = await MediaCrypto.instance.encrypt(bytes);
      final encFile = File('${rawFile.path}.enc');
      await encFile.writeAsBytes(encrypted.ciphertext, flush: true);
      await rawFile.delete();

      // Raw file is purged, enc file exists with ciphertext
      expect(rawFile.existsSync(), isFalse);
      expect(encFile.existsSync(), isTrue);

      final readEncryptedBytes = await encFile.readAsBytes();
      expect(readEncryptedBytes, isNot(equals([1, 2, 3, 4, 5, 6, 7, 8])));

      final decrypted = await MediaCrypto.instance.decrypt(
        readEncryptedBytes,
        encrypted.mediaKeyBase64,
      );
      expect(decrypted, equals(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])));

      // Cleanup
      await encFile.delete();
    },
  );
}
