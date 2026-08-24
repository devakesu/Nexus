import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'signal_database.g.dart';

/// Single-row table holding this device's Signal identity key pair and
/// registration id. Never leaves the device; only the derived public key
/// is ever uploaded (see `signal_key_service.dart`).
class LocalIdentities extends Table {
  IntColumn get id => integer()();
  BlobColumn get identityKeyPairEnc => blob()();
  IntColumn get registrationId => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One-time prekeys generated locally; private halves never leave the
/// device. Removed once consumed by an incoming PreKeySignalMessage.
class PreKeys extends Table {
  IntColumn get keyId => integer()();
  BlobColumn get recordEnc => blob()();

  @override
  Set<Column> get primaryKey => {keyId};
}

/// Signed prekeys generated locally; rotated periodically.
class SignedPreKeys extends Table {
  IntColumn get keyId => integer()();
  BlobColumn get recordEnc => blob()();

  @override
  Set<Column> get primaryKey => {keyId};
}

/// Double Ratchet session state per remote SignalProtocolAddress
/// ("$name:$deviceId"). This is the single most sensitive table - it holds
/// chain keys and the skipped-message-key cache.
class Sessions extends Table {
  TextColumn get address => text()();
  BlobColumn get recordEnc => blob()();

  @override
  Set<Column> get primaryKey => {address};
}

/// Identity keys we've observed for remote addresses, used for
/// isTrustedIdentity()/saveIdentity() (basic TOFU trust-on-first-use).
class TrustedIdentities extends Table {
  TextColumn get address => text()();
  BlobColumn get identityKeyEnc => blob()();

  @override
  Set<Column> get primaryKey => {address};
}

/// Local plaintext cache, keyed by server message id. Double Ratchet
/// message keys are deleted immediately after a successful decrypt (that's
/// the forward-secrecy property), so re-fetching the same ciphertext from
/// the server a second time (e.g. reopening the chat) cannot be decrypted
/// again. Every message - sent or received - is decrypted/encrypted at
/// most once and its plaintext cached here (itself vault-encrypted) for
/// every subsequent read.
class LocalMessages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text()();
  TextColumn get senderId => text()();
  BoolColumn get isMine => boolean()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get messageType => text()();
  BlobColumn get plaintextEnc => blob().nullable()();
  BoolColumn get decryptFailed =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local disk cache of decrypted chat attachment bytes, keyed by the
/// attachment's storage path (stable and globally unique per attachment -
/// see `MediaPointer.storagePath` / `_sendMedia`'s `'$conversationId/$userId/$uuid.enc'`
/// construction). Same at-rest protection as `LocalMessages.plaintextEnc`:
/// vault-encrypted via `LocalKeyVault`, not just OS file sandboxing. Exists
/// purely to avoid re-downloading from Storage and re-running `MediaCrypto`
/// decryption every time an image/voice bubble scrolls back into view.
class CachedMedia extends Table {
  TextColumn get storagePath => text()();
  BlobColumn get plaintextEnc => blob()();
  TextColumn get mimeType => text()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {storagePath};
}

@DriftDatabase(
  tables: [
    LocalIdentities,
    PreKeys,
    SignedPreKeys,
    Sessions,
    TrustedIdentities,
    LocalMessages,
    CachedMedia,
  ],
)
class SignalDatabase extends _$SignalDatabase {
  SignalDatabase._() : super(driftDatabase(name: 'nexus_signal_store'));

  /// Single shared instance - Signal session state and the local message
  /// cache must never be opened from two separate connections at once.
  static final SignalDatabase instance = SignalDatabase._();

  @override
  int get schemaVersion => 2;

  // This database already holds live Signal session/identity keys and
  // cached message plaintext in production, so schema bumps must never
  // fall back to drift's default "wipe and recreate everything" upgrade -
  // that would force every existing conversation into the "new device,
  // undecryptable history" state. Only ever add tables here going forward.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(cachedMedia);
      }
    },
  );

  Future<void> clearAllData() async {
    await transaction(() async {
      for (final table in allTables) {
        await delete(table).go();
      }
    });
  }
}
