import 'package:drift/drift.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:nexus/services/signal/local_key_vault.dart';
import 'package:nexus/services/signal/signal_database.dart';

/// Drift-backed [SignalProtocolStore]. Every blob written to disk is
/// AES-256-GCM encrypted first via [LocalKeyVault] - this table holds the
/// most sensitive data in the app (private keys, Double Ratchet chain
/// state), so it gets the same treatment SQLCipher whole-database
/// encryption would, applied at the column level instead (see
/// `local_key_vault.dart` for why: `sqlcipher_flutter_libs` is EOL and its
/// replacement requires an experimental native-build-hooks mechanism we're
/// not depending on yet).
class DriftSignalProtocolStore extends IdentityKeyStore
    with PreKeyStore, SessionStore, SignedPreKeyStore
    implements SignalProtocolStore {
  DriftSignalProtocolStore(
    this._db,
    this._identityKeyPair,
    this._registrationId,
  );

  final SignalDatabase _db;
  final IdentityKeyPair _identityKeyPair;
  final int _registrationId;
  final LocalKeyVault _vault = LocalKeyVault.instance;

  // --- IdentityKeyStore ---

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async => _identityKeyPair;

  @override
  Future<int> getLocalRegistrationId() async => _registrationId;

  @override
  Future<bool> saveIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
  ) async {
    if (identityKey == null) return false;

    final existing = await getIdentity(address);
    final changed =
        existing == null ||
        !_bytesEqual(existing.serialize(), identityKey.serialize());

    final encrypted = await _vault.encryptBytes(identityKey.serialize());
    await _db
        .into(_db.trustedIdentities)
        .insertOnConflictUpdate(
          TrustedIdentitiesCompanion.insert(
            address: address.toString(),
            identityKeyEnc: encrypted,
          ),
        );
    return changed;
  }

  @override
  Future<bool> isTrustedIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
    Direction direction,
  ) async {
    if (identityKey == null) return false;
    // Trust-on-first-use: an address we've never seen before is trusted;
    // once pinned, the identity key must match on every future session.
    final existing = await getIdentity(address);
    return existing == null ||
        _bytesEqual(existing.serialize(), identityKey.serialize());
  }

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final row = await (_db.select(
      _db.trustedIdentities,
    )..where((t) => t.address.equals(address.toString()))).getSingleOrNull();
    if (row == null) return null;
    final decrypted = await _vault.decryptBytes(
      Uint8List.fromList(row.identityKeyEnc),
    );
    return IdentityKey.fromBytes(decrypted, 0);
  }

  // --- PreKeyStore ---

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final row = await (_db.select(
      _db.preKeys,
    )..where((t) => t.keyId.equals(preKeyId))).getSingleOrNull();
    if (row == null) {
      throw InvalidKeyIdException('No such prekey: $preKeyId');
    }
    final decrypted = await _vault.decryptBytes(
      Uint8List.fromList(row.recordEnc),
    );
    return PreKeyRecord.fromBuffer(decrypted);
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) async {
    final encrypted = await _vault.encryptBytes(record.serialize());
    await _db
        .into(_db.preKeys)
        .insertOnConflictUpdate(
          PreKeysCompanion.insert(
            keyId: Value(preKeyId),
            recordEnc: encrypted,
          ),
        );
  }

  @override
  Future<bool> containsPreKey(int preKeyId) async {
    final row = await (_db.select(
      _db.preKeys,
    )..where((t) => t.keyId.equals(preKeyId))).getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> removePreKey(int preKeyId) async {
    await (_db.delete(
      _db.preKeys,
    )..where((t) => t.keyId.equals(preKeyId))).go();
  }

  // --- SignedPreKeyStore ---

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final row = await (_db.select(
      _db.signedPreKeys,
    )..where((t) => t.keyId.equals(signedPreKeyId))).getSingleOrNull();
    if (row == null) {
      throw InvalidKeyIdException('No such signed prekey: $signedPreKeyId');
    }
    final decrypted = await _vault.decryptBytes(
      Uint8List.fromList(row.recordEnc),
    );
    return SignedPreKeyRecord.fromSerialized(decrypted);
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async {
    final rows = await _db.select(_db.signedPreKeys).get();
    final records = <SignedPreKeyRecord>[];
    for (final row in rows) {
      final decrypted = await _vault.decryptBytes(
        Uint8List.fromList(row.recordEnc),
      );
      records.add(SignedPreKeyRecord.fromSerialized(decrypted));
    }
    return records;
  }

  @override
  Future<void> storeSignedPreKey(
    int signedPreKeyId,
    SignedPreKeyRecord record,
  ) async {
    final encrypted = await _vault.encryptBytes(record.serialize());
    await _db
        .into(_db.signedPreKeys)
        .insertOnConflictUpdate(
          SignedPreKeysCompanion.insert(
            keyId: Value(signedPreKeyId),
            recordEnc: encrypted,
          ),
        );
  }

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) async {
    final row = await (_db.select(
      _db.signedPreKeys,
    )..where((t) => t.keyId.equals(signedPreKeyId))).getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) async {
    await (_db.delete(
      _db.signedPreKeys,
    )..where((t) => t.keyId.equals(signedPreKeyId))).go();
  }

  // --- SessionStore ---

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final row = await (_db.select(
      _db.sessions,
    )..where((t) => t.address.equals(address.toString()))).getSingleOrNull();
    if (row == null) return SessionRecord();
    final decrypted = await _vault.decryptBytes(
      Uint8List.fromList(row.recordEnc),
    );
    return SessionRecord.fromSerialized(decrypted);
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async {
    final rows = await _db.select(_db.sessions).get();
    final deviceIds = <int>[];
    for (final row in rows) {
      final parts = row.address.split(':');
      if (parts.length == 2 && parts[0] == name) {
        final deviceId = int.tryParse(parts[1]);
        if (deviceId != null && deviceId != 1) deviceIds.add(deviceId);
      }
    }
    return deviceIds;
  }

  @override
  Future<void> storeSession(
    SignalProtocolAddress address,
    SessionRecord record,
  ) async {
    final encrypted = await _vault.encryptBytes(record.serialize());
    await _db
        .into(_db.sessions)
        .insertOnConflictUpdate(
          SessionsCompanion.insert(
            address: address.toString(),
            recordEnc: encrypted,
          ),
        );
  }

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async {
    final row = await (_db.select(
      _db.sessions,
    )..where((t) => t.address.equals(address.toString()))).getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> deleteSession(SignalProtocolAddress address) async {
    await (_db.delete(
      _db.sessions,
    )..where((t) => t.address.equals(address.toString()))).go();
  }

  @override
  Future<void> deleteAllSessions(String name) async {
    await (_db.delete(
      _db.sessions,
    )..where((t) => t.address.like('$name:%'))).go();
  }
}

/// Constant-time comparison - identity key bytes are security-sensitive, so
/// this must not short-circuit on the first mismatching byte the way a
/// plain loop-with-early-return would.
bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
