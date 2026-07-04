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

@DriftDatabase(
  tables: [LocalIdentities, PreKeys, SignedPreKeys, Sessions, TrustedIdentities],
)
class SignalDatabase extends _$SignalDatabase {
  SignalDatabase() : super(driftDatabase(name: 'nexus_signal_store'));

  @override
  int get schemaVersion => 1;
}
