import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/signal/local_key_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  test(
    'Encrypted media cache writes, reads, and purges from disk cleanly',
    () async {
      final tempDir = Directory.systemTemp;
      final cacheDir = Directory(
        '${tempDir.path}/test_chat_media_cache_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }

      try {
        const storagePath = 'conv123/user456/attachment.enc';
        final safeFileName = base64Url
            .encode(utf8.encode(storagePath))
            .replaceAll('=', '');
        final cacheFile = File('${cacheDir.path}/$safeFileName.enc');

        final samplePlaintext = Uint8List.fromList(
          List.generate(1024 * 64, (i) => i % 256),
        );

        // 1. Vault encrypt & write to disk
        final encrypted = await LocalKeyVault.instance.encryptBytes(
          samplePlaintext,
        );
        await cacheFile.writeAsBytes(encrypted, flush: true);

        expect(cacheFile.existsSync(), isTrue);
        expect(
          cacheFile.lengthSync(),
          greaterThanOrEqualTo(samplePlaintext.length),
        );

        // 2. Read back & decrypt
        final readBytes = await cacheFile.readAsBytes();
        final decrypted = await LocalKeyVault.instance.decryptBytes(readBytes);
        expect(decrypted, equals(samplePlaintext));

        // 3. Purge disk cache
        if (cacheFile.existsSync()) {
          cacheFile.deleteSync();
        }
        expect(cacheFile.existsSync(), isFalse);
      } finally {
        if (cacheDir.existsSync()) {
          cacheDir.deleteSync(recursive: true);
        }
      }
    },
  );
}
