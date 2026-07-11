// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'signal_database.dart';

// ignore_for_file: type=lint
class $LocalIdentitiesTable extends LocalIdentities
    with TableInfo<$LocalIdentitiesTable, LocalIdentity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalIdentitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _identityKeyPairEncMeta =
      const VerificationMeta('identityKeyPairEnc');
  @override
  late final GeneratedColumn<Uint8List> identityKeyPairEnc =
      GeneratedColumn<Uint8List>(
        'identity_key_pair_enc',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _registrationIdMeta = const VerificationMeta(
    'registrationId',
  );
  @override
  late final GeneratedColumn<int> registrationId = GeneratedColumn<int>(
    'registration_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    identityKeyPairEnc,
    registrationId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_identities';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalIdentity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('identity_key_pair_enc')) {
      context.handle(
        _identityKeyPairEncMeta,
        identityKeyPairEnc.isAcceptableOrUnknown(
          data['identity_key_pair_enc']!,
          _identityKeyPairEncMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_identityKeyPairEncMeta);
    }
    if (data.containsKey('registration_id')) {
      context.handle(
        _registrationIdMeta,
        registrationId.isAcceptableOrUnknown(
          data['registration_id']!,
          _registrationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_registrationIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalIdentity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalIdentity(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      identityKeyPairEnc: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}identity_key_pair_enc'],
      )!,
      registrationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}registration_id'],
      )!,
    );
  }

  @override
  $LocalIdentitiesTable createAlias(String alias) {
    return $LocalIdentitiesTable(attachedDatabase, alias);
  }
}

class LocalIdentity extends DataClass implements Insertable<LocalIdentity> {
  final int id;
  final Uint8List identityKeyPairEnc;
  final int registrationId;
  const LocalIdentity({
    required this.id,
    required this.identityKeyPairEnc,
    required this.registrationId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['identity_key_pair_enc'] = Variable<Uint8List>(identityKeyPairEnc);
    map['registration_id'] = Variable<int>(registrationId);
    return map;
  }

  LocalIdentitiesCompanion toCompanion(bool nullToAbsent) {
    return LocalIdentitiesCompanion(
      id: Value(id),
      identityKeyPairEnc: Value(identityKeyPairEnc),
      registrationId: Value(registrationId),
    );
  }

  factory LocalIdentity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalIdentity(
      id: serializer.fromJson<int>(json['id']),
      identityKeyPairEnc: serializer.fromJson<Uint8List>(
        json['identityKeyPairEnc'],
      ),
      registrationId: serializer.fromJson<int>(json['registrationId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'identityKeyPairEnc': serializer.toJson<Uint8List>(identityKeyPairEnc),
      'registrationId': serializer.toJson<int>(registrationId),
    };
  }

  LocalIdentity copyWith({
    int? id,
    Uint8List? identityKeyPairEnc,
    int? registrationId,
  }) => LocalIdentity(
    id: id ?? this.id,
    identityKeyPairEnc: identityKeyPairEnc ?? this.identityKeyPairEnc,
    registrationId: registrationId ?? this.registrationId,
  );
  LocalIdentity copyWithCompanion(LocalIdentitiesCompanion data) {
    return LocalIdentity(
      id: data.id.present ? data.id.value : this.id,
      identityKeyPairEnc: data.identityKeyPairEnc.present
          ? data.identityKeyPairEnc.value
          : this.identityKeyPairEnc,
      registrationId: data.registrationId.present
          ? data.registrationId.value
          : this.registrationId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalIdentity(')
          ..write('id: $id, ')
          ..write('identityKeyPairEnc: $identityKeyPairEnc, ')
          ..write('registrationId: $registrationId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    $driftBlobEquality.hash(identityKeyPairEnc),
    registrationId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalIdentity &&
          other.id == this.id &&
          $driftBlobEquality.equals(
            other.identityKeyPairEnc,
            this.identityKeyPairEnc,
          ) &&
          other.registrationId == this.registrationId);
}

class LocalIdentitiesCompanion extends UpdateCompanion<LocalIdentity> {
  final Value<int> id;
  final Value<Uint8List> identityKeyPairEnc;
  final Value<int> registrationId;
  const LocalIdentitiesCompanion({
    this.id = const Value.absent(),
    this.identityKeyPairEnc = const Value.absent(),
    this.registrationId = const Value.absent(),
  });
  LocalIdentitiesCompanion.insert({
    this.id = const Value.absent(),
    required Uint8List identityKeyPairEnc,
    required int registrationId,
  }) : identityKeyPairEnc = Value(identityKeyPairEnc),
       registrationId = Value(registrationId);
  static Insertable<LocalIdentity> custom({
    Expression<int>? id,
    Expression<Uint8List>? identityKeyPairEnc,
    Expression<int>? registrationId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (identityKeyPairEnc != null)
        'identity_key_pair_enc': identityKeyPairEnc,
      if (registrationId != null) 'registration_id': registrationId,
    });
  }

  LocalIdentitiesCompanion copyWith({
    Value<int>? id,
    Value<Uint8List>? identityKeyPairEnc,
    Value<int>? registrationId,
  }) {
    return LocalIdentitiesCompanion(
      id: id ?? this.id,
      identityKeyPairEnc: identityKeyPairEnc ?? this.identityKeyPairEnc,
      registrationId: registrationId ?? this.registrationId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (identityKeyPairEnc.present) {
      map['identity_key_pair_enc'] = Variable<Uint8List>(
        identityKeyPairEnc.value,
      );
    }
    if (registrationId.present) {
      map['registration_id'] = Variable<int>(registrationId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalIdentitiesCompanion(')
          ..write('id: $id, ')
          ..write('identityKeyPairEnc: $identityKeyPairEnc, ')
          ..write('registrationId: $registrationId')
          ..write(')'))
        .toString();
  }
}

class $PreKeysTable extends PreKeys with TableInfo<$PreKeysTable, PreKey> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PreKeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyIdMeta = const VerificationMeta('keyId');
  @override
  late final GeneratedColumn<int> keyId = GeneratedColumn<int>(
    'key_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recordEncMeta = const VerificationMeta(
    'recordEnc',
  );
  @override
  late final GeneratedColumn<Uint8List> recordEnc = GeneratedColumn<Uint8List>(
    'record_enc',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [keyId, recordEnc];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pre_keys';
  @override
  VerificationContext validateIntegrity(
    Insertable<PreKey> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key_id')) {
      context.handle(
        _keyIdMeta,
        keyId.isAcceptableOrUnknown(data['key_id']!, _keyIdMeta),
      );
    }
    if (data.containsKey('record_enc')) {
      context.handle(
        _recordEncMeta,
        recordEnc.isAcceptableOrUnknown(data['record_enc']!, _recordEncMeta),
      );
    } else if (isInserting) {
      context.missing(_recordEncMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {keyId};
  @override
  PreKey map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PreKey(
      keyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}key_id'],
      )!,
      recordEnc: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}record_enc'],
      )!,
    );
  }

  @override
  $PreKeysTable createAlias(String alias) {
    return $PreKeysTable(attachedDatabase, alias);
  }
}

class PreKey extends DataClass implements Insertable<PreKey> {
  final int keyId;
  final Uint8List recordEnc;
  const PreKey({required this.keyId, required this.recordEnc});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key_id'] = Variable<int>(keyId);
    map['record_enc'] = Variable<Uint8List>(recordEnc);
    return map;
  }

  PreKeysCompanion toCompanion(bool nullToAbsent) {
    return PreKeysCompanion(keyId: Value(keyId), recordEnc: Value(recordEnc));
  }

  factory PreKey.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PreKey(
      keyId: serializer.fromJson<int>(json['keyId']),
      recordEnc: serializer.fromJson<Uint8List>(json['recordEnc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'keyId': serializer.toJson<int>(keyId),
      'recordEnc': serializer.toJson<Uint8List>(recordEnc),
    };
  }

  PreKey copyWith({int? keyId, Uint8List? recordEnc}) => PreKey(
    keyId: keyId ?? this.keyId,
    recordEnc: recordEnc ?? this.recordEnc,
  );
  PreKey copyWithCompanion(PreKeysCompanion data) {
    return PreKey(
      keyId: data.keyId.present ? data.keyId.value : this.keyId,
      recordEnc: data.recordEnc.present ? data.recordEnc.value : this.recordEnc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PreKey(')
          ..write('keyId: $keyId, ')
          ..write('recordEnc: $recordEnc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(keyId, $driftBlobEquality.hash(recordEnc));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PreKey &&
          other.keyId == this.keyId &&
          $driftBlobEquality.equals(other.recordEnc, this.recordEnc));
}

class PreKeysCompanion extends UpdateCompanion<PreKey> {
  final Value<int> keyId;
  final Value<Uint8List> recordEnc;
  const PreKeysCompanion({
    this.keyId = const Value.absent(),
    this.recordEnc = const Value.absent(),
  });
  PreKeysCompanion.insert({
    this.keyId = const Value.absent(),
    required Uint8List recordEnc,
  }) : recordEnc = Value(recordEnc);
  static Insertable<PreKey> custom({
    Expression<int>? keyId,
    Expression<Uint8List>? recordEnc,
  }) {
    return RawValuesInsertable({
      if (keyId != null) 'key_id': keyId,
      if (recordEnc != null) 'record_enc': recordEnc,
    });
  }

  PreKeysCompanion copyWith({Value<int>? keyId, Value<Uint8List>? recordEnc}) {
    return PreKeysCompanion(
      keyId: keyId ?? this.keyId,
      recordEnc: recordEnc ?? this.recordEnc,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (keyId.present) {
      map['key_id'] = Variable<int>(keyId.value);
    }
    if (recordEnc.present) {
      map['record_enc'] = Variable<Uint8List>(recordEnc.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PreKeysCompanion(')
          ..write('keyId: $keyId, ')
          ..write('recordEnc: $recordEnc')
          ..write(')'))
        .toString();
  }
}

class $SignedPreKeysTable extends SignedPreKeys
    with TableInfo<$SignedPreKeysTable, SignedPreKey> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SignedPreKeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyIdMeta = const VerificationMeta('keyId');
  @override
  late final GeneratedColumn<int> keyId = GeneratedColumn<int>(
    'key_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recordEncMeta = const VerificationMeta(
    'recordEnc',
  );
  @override
  late final GeneratedColumn<Uint8List> recordEnc = GeneratedColumn<Uint8List>(
    'record_enc',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [keyId, recordEnc];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'signed_pre_keys';
  @override
  VerificationContext validateIntegrity(
    Insertable<SignedPreKey> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key_id')) {
      context.handle(
        _keyIdMeta,
        keyId.isAcceptableOrUnknown(data['key_id']!, _keyIdMeta),
      );
    }
    if (data.containsKey('record_enc')) {
      context.handle(
        _recordEncMeta,
        recordEnc.isAcceptableOrUnknown(data['record_enc']!, _recordEncMeta),
      );
    } else if (isInserting) {
      context.missing(_recordEncMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {keyId};
  @override
  SignedPreKey map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SignedPreKey(
      keyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}key_id'],
      )!,
      recordEnc: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}record_enc'],
      )!,
    );
  }

  @override
  $SignedPreKeysTable createAlias(String alias) {
    return $SignedPreKeysTable(attachedDatabase, alias);
  }
}

class SignedPreKey extends DataClass implements Insertable<SignedPreKey> {
  final int keyId;
  final Uint8List recordEnc;
  const SignedPreKey({required this.keyId, required this.recordEnc});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key_id'] = Variable<int>(keyId);
    map['record_enc'] = Variable<Uint8List>(recordEnc);
    return map;
  }

  SignedPreKeysCompanion toCompanion(bool nullToAbsent) {
    return SignedPreKeysCompanion(
      keyId: Value(keyId),
      recordEnc: Value(recordEnc),
    );
  }

  factory SignedPreKey.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SignedPreKey(
      keyId: serializer.fromJson<int>(json['keyId']),
      recordEnc: serializer.fromJson<Uint8List>(json['recordEnc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'keyId': serializer.toJson<int>(keyId),
      'recordEnc': serializer.toJson<Uint8List>(recordEnc),
    };
  }

  SignedPreKey copyWith({int? keyId, Uint8List? recordEnc}) => SignedPreKey(
    keyId: keyId ?? this.keyId,
    recordEnc: recordEnc ?? this.recordEnc,
  );
  SignedPreKey copyWithCompanion(SignedPreKeysCompanion data) {
    return SignedPreKey(
      keyId: data.keyId.present ? data.keyId.value : this.keyId,
      recordEnc: data.recordEnc.present ? data.recordEnc.value : this.recordEnc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SignedPreKey(')
          ..write('keyId: $keyId, ')
          ..write('recordEnc: $recordEnc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(keyId, $driftBlobEquality.hash(recordEnc));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SignedPreKey &&
          other.keyId == this.keyId &&
          $driftBlobEquality.equals(other.recordEnc, this.recordEnc));
}

class SignedPreKeysCompanion extends UpdateCompanion<SignedPreKey> {
  final Value<int> keyId;
  final Value<Uint8List> recordEnc;
  const SignedPreKeysCompanion({
    this.keyId = const Value.absent(),
    this.recordEnc = const Value.absent(),
  });
  SignedPreKeysCompanion.insert({
    this.keyId = const Value.absent(),
    required Uint8List recordEnc,
  }) : recordEnc = Value(recordEnc);
  static Insertable<SignedPreKey> custom({
    Expression<int>? keyId,
    Expression<Uint8List>? recordEnc,
  }) {
    return RawValuesInsertable({
      if (keyId != null) 'key_id': keyId,
      if (recordEnc != null) 'record_enc': recordEnc,
    });
  }

  SignedPreKeysCompanion copyWith({
    Value<int>? keyId,
    Value<Uint8List>? recordEnc,
  }) {
    return SignedPreKeysCompanion(
      keyId: keyId ?? this.keyId,
      recordEnc: recordEnc ?? this.recordEnc,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (keyId.present) {
      map['key_id'] = Variable<int>(keyId.value);
    }
    if (recordEnc.present) {
      map['record_enc'] = Variable<Uint8List>(recordEnc.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SignedPreKeysCompanion(')
          ..write('keyId: $keyId, ')
          ..write('recordEnc: $recordEnc')
          ..write(')'))
        .toString();
  }
}

class $SessionsTable extends Sessions with TableInfo<$SessionsTable, Session> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordEncMeta = const VerificationMeta(
    'recordEnc',
  );
  @override
  late final GeneratedColumn<Uint8List> recordEnc = GeneratedColumn<Uint8List>(
    'record_enc',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [address, recordEnc];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Session> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    } else if (isInserting) {
      context.missing(_addressMeta);
    }
    if (data.containsKey('record_enc')) {
      context.handle(
        _recordEncMeta,
        recordEnc.isAcceptableOrUnknown(data['record_enc']!, _recordEncMeta),
      );
    } else if (isInserting) {
      context.missing(_recordEncMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {address};
  @override
  Session map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Session(
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      )!,
      recordEnc: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}record_enc'],
      )!,
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }
}

class Session extends DataClass implements Insertable<Session> {
  final String address;
  final Uint8List recordEnc;
  const Session({required this.address, required this.recordEnc});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['address'] = Variable<String>(address);
    map['record_enc'] = Variable<Uint8List>(recordEnc);
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      address: Value(address),
      recordEnc: Value(recordEnc),
    );
  }

  factory Session.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Session(
      address: serializer.fromJson<String>(json['address']),
      recordEnc: serializer.fromJson<Uint8List>(json['recordEnc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'address': serializer.toJson<String>(address),
      'recordEnc': serializer.toJson<Uint8List>(recordEnc),
    };
  }

  Session copyWith({String? address, Uint8List? recordEnc}) => Session(
    address: address ?? this.address,
    recordEnc: recordEnc ?? this.recordEnc,
  );
  Session copyWithCompanion(SessionsCompanion data) {
    return Session(
      address: data.address.present ? data.address.value : this.address,
      recordEnc: data.recordEnc.present ? data.recordEnc.value : this.recordEnc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Session(')
          ..write('address: $address, ')
          ..write('recordEnc: $recordEnc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(address, $driftBlobEquality.hash(recordEnc));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Session &&
          other.address == this.address &&
          $driftBlobEquality.equals(other.recordEnc, this.recordEnc));
}

class SessionsCompanion extends UpdateCompanion<Session> {
  final Value<String> address;
  final Value<Uint8List> recordEnc;
  final Value<int> rowid;
  const SessionsCompanion({
    this.address = const Value.absent(),
    this.recordEnc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String address,
    required Uint8List recordEnc,
    this.rowid = const Value.absent(),
  }) : address = Value(address),
       recordEnc = Value(recordEnc);
  static Insertable<Session> custom({
    Expression<String>? address,
    Expression<Uint8List>? recordEnc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (address != null) 'address': address,
      if (recordEnc != null) 'record_enc': recordEnc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? address,
    Value<Uint8List>? recordEnc,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      address: address ?? this.address,
      recordEnc: recordEnc ?? this.recordEnc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (recordEnc.present) {
      map['record_enc'] = Variable<Uint8List>(recordEnc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('address: $address, ')
          ..write('recordEnc: $recordEnc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TrustedIdentitiesTable extends TrustedIdentities
    with TableInfo<$TrustedIdentitiesTable, TrustedIdentity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrustedIdentitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _identityKeyEncMeta = const VerificationMeta(
    'identityKeyEnc',
  );
  @override
  late final GeneratedColumn<Uint8List> identityKeyEnc =
      GeneratedColumn<Uint8List>(
        'identity_key_enc',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [address, identityKeyEnc];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trusted_identities';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrustedIdentity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    } else if (isInserting) {
      context.missing(_addressMeta);
    }
    if (data.containsKey('identity_key_enc')) {
      context.handle(
        _identityKeyEncMeta,
        identityKeyEnc.isAcceptableOrUnknown(
          data['identity_key_enc']!,
          _identityKeyEncMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_identityKeyEncMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {address};
  @override
  TrustedIdentity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrustedIdentity(
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      )!,
      identityKeyEnc: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}identity_key_enc'],
      )!,
    );
  }

  @override
  $TrustedIdentitiesTable createAlias(String alias) {
    return $TrustedIdentitiesTable(attachedDatabase, alias);
  }
}

class TrustedIdentity extends DataClass implements Insertable<TrustedIdentity> {
  final String address;
  final Uint8List identityKeyEnc;
  const TrustedIdentity({required this.address, required this.identityKeyEnc});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['address'] = Variable<String>(address);
    map['identity_key_enc'] = Variable<Uint8List>(identityKeyEnc);
    return map;
  }

  TrustedIdentitiesCompanion toCompanion(bool nullToAbsent) {
    return TrustedIdentitiesCompanion(
      address: Value(address),
      identityKeyEnc: Value(identityKeyEnc),
    );
  }

  factory TrustedIdentity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrustedIdentity(
      address: serializer.fromJson<String>(json['address']),
      identityKeyEnc: serializer.fromJson<Uint8List>(json['identityKeyEnc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'address': serializer.toJson<String>(address),
      'identityKeyEnc': serializer.toJson<Uint8List>(identityKeyEnc),
    };
  }

  TrustedIdentity copyWith({String? address, Uint8List? identityKeyEnc}) =>
      TrustedIdentity(
        address: address ?? this.address,
        identityKeyEnc: identityKeyEnc ?? this.identityKeyEnc,
      );
  TrustedIdentity copyWithCompanion(TrustedIdentitiesCompanion data) {
    return TrustedIdentity(
      address: data.address.present ? data.address.value : this.address,
      identityKeyEnc: data.identityKeyEnc.present
          ? data.identityKeyEnc.value
          : this.identityKeyEnc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrustedIdentity(')
          ..write('address: $address, ')
          ..write('identityKeyEnc: $identityKeyEnc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(address, $driftBlobEquality.hash(identityKeyEnc));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrustedIdentity &&
          other.address == this.address &&
          $driftBlobEquality.equals(other.identityKeyEnc, this.identityKeyEnc));
}

class TrustedIdentitiesCompanion extends UpdateCompanion<TrustedIdentity> {
  final Value<String> address;
  final Value<Uint8List> identityKeyEnc;
  final Value<int> rowid;
  const TrustedIdentitiesCompanion({
    this.address = const Value.absent(),
    this.identityKeyEnc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TrustedIdentitiesCompanion.insert({
    required String address,
    required Uint8List identityKeyEnc,
    this.rowid = const Value.absent(),
  }) : address = Value(address),
       identityKeyEnc = Value(identityKeyEnc);
  static Insertable<TrustedIdentity> custom({
    Expression<String>? address,
    Expression<Uint8List>? identityKeyEnc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (address != null) 'address': address,
      if (identityKeyEnc != null) 'identity_key_enc': identityKeyEnc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TrustedIdentitiesCompanion copyWith({
    Value<String>? address,
    Value<Uint8List>? identityKeyEnc,
    Value<int>? rowid,
  }) {
    return TrustedIdentitiesCompanion(
      address: address ?? this.address,
      identityKeyEnc: identityKeyEnc ?? this.identityKeyEnc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (identityKeyEnc.present) {
      map['identity_key_enc'] = Variable<Uint8List>(identityKeyEnc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrustedIdentitiesCompanion(')
          ..write('address: $address, ')
          ..write('identityKeyEnc: $identityKeyEnc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalMessagesTable extends LocalMessages
    with TableInfo<$LocalMessagesTable, LocalMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderIdMeta = const VerificationMeta(
    'senderId',
  );
  @override
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
    'sender_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isMineMeta = const VerificationMeta('isMine');
  @override
  late final GeneratedColumn<bool> isMine = GeneratedColumn<bool>(
    'is_mine',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_mine" IN (0, 1))',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageTypeMeta = const VerificationMeta(
    'messageType',
  );
  @override
  late final GeneratedColumn<String> messageType = GeneratedColumn<String>(
    'message_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _plaintextEncMeta = const VerificationMeta(
    'plaintextEnc',
  );
  @override
  late final GeneratedColumn<Uint8List> plaintextEnc =
      GeneratedColumn<Uint8List>(
        'plaintext_enc',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _decryptFailedMeta = const VerificationMeta(
    'decryptFailed',
  );
  @override
  late final GeneratedColumn<bool> decryptFailed = GeneratedColumn<bool>(
    'decrypt_failed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("decrypt_failed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    senderId,
    isMine,
    createdAt,
    messageType,
    plaintextEnc,
    decryptFailed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(
        _senderIdMeta,
        senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('is_mine')) {
      context.handle(
        _isMineMeta,
        isMine.isAcceptableOrUnknown(data['is_mine']!, _isMineMeta),
      );
    } else if (isInserting) {
      context.missing(_isMineMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('message_type')) {
      context.handle(
        _messageTypeMeta,
        messageType.isAcceptableOrUnknown(
          data['message_type']!,
          _messageTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_messageTypeMeta);
    }
    if (data.containsKey('plaintext_enc')) {
      context.handle(
        _plaintextEncMeta,
        plaintextEnc.isAcceptableOrUnknown(
          data['plaintext_enc']!,
          _plaintextEncMeta,
        ),
      );
    }
    if (data.containsKey('decrypt_failed')) {
      context.handle(
        _decryptFailedMeta,
        decryptFailed.isAcceptableOrUnknown(
          data['decrypt_failed']!,
          _decryptFailedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      senderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_id'],
      )!,
      isMine: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_mine'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      messageType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_type'],
      )!,
      plaintextEnc: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}plaintext_enc'],
      ),
      decryptFailed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}decrypt_failed'],
      )!,
    );
  }

  @override
  $LocalMessagesTable createAlias(String alias) {
    return $LocalMessagesTable(attachedDatabase, alias);
  }
}

class LocalMessage extends DataClass implements Insertable<LocalMessage> {
  final String id;
  final String conversationId;
  final String senderId;
  final bool isMine;
  final DateTime createdAt;
  final String messageType;
  final Uint8List? plaintextEnc;
  final bool decryptFailed;
  const LocalMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.isMine,
    required this.createdAt,
    required this.messageType,
    this.plaintextEnc,
    required this.decryptFailed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['sender_id'] = Variable<String>(senderId);
    map['is_mine'] = Variable<bool>(isMine);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['message_type'] = Variable<String>(messageType);
    if (!nullToAbsent || plaintextEnc != null) {
      map['plaintext_enc'] = Variable<Uint8List>(plaintextEnc);
    }
    map['decrypt_failed'] = Variable<bool>(decryptFailed);
    return map;
  }

  LocalMessagesCompanion toCompanion(bool nullToAbsent) {
    return LocalMessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      senderId: Value(senderId),
      isMine: Value(isMine),
      createdAt: Value(createdAt),
      messageType: Value(messageType),
      plaintextEnc: plaintextEnc == null && nullToAbsent
          ? const Value.absent()
          : Value(plaintextEnc),
      decryptFailed: Value(decryptFailed),
    );
  }

  factory LocalMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalMessage(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      senderId: serializer.fromJson<String>(json['senderId']),
      isMine: serializer.fromJson<bool>(json['isMine']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      messageType: serializer.fromJson<String>(json['messageType']),
      plaintextEnc: serializer.fromJson<Uint8List?>(json['plaintextEnc']),
      decryptFailed: serializer.fromJson<bool>(json['decryptFailed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'senderId': serializer.toJson<String>(senderId),
      'isMine': serializer.toJson<bool>(isMine),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'messageType': serializer.toJson<String>(messageType),
      'plaintextEnc': serializer.toJson<Uint8List?>(plaintextEnc),
      'decryptFailed': serializer.toJson<bool>(decryptFailed),
    };
  }

  LocalMessage copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    bool? isMine,
    DateTime? createdAt,
    String? messageType,
    Value<Uint8List?> plaintextEnc = const Value.absent(),
    bool? decryptFailed,
  }) => LocalMessage(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    senderId: senderId ?? this.senderId,
    isMine: isMine ?? this.isMine,
    createdAt: createdAt ?? this.createdAt,
    messageType: messageType ?? this.messageType,
    plaintextEnc: plaintextEnc.present ? plaintextEnc.value : this.plaintextEnc,
    decryptFailed: decryptFailed ?? this.decryptFailed,
  );
  LocalMessage copyWithCompanion(LocalMessagesCompanion data) {
    return LocalMessage(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      isMine: data.isMine.present ? data.isMine.value : this.isMine,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      messageType: data.messageType.present
          ? data.messageType.value
          : this.messageType,
      plaintextEnc: data.plaintextEnc.present
          ? data.plaintextEnc.value
          : this.plaintextEnc,
      decryptFailed: data.decryptFailed.present
          ? data.decryptFailed.value
          : this.decryptFailed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalMessage(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('isMine: $isMine, ')
          ..write('createdAt: $createdAt, ')
          ..write('messageType: $messageType, ')
          ..write('plaintextEnc: $plaintextEnc, ')
          ..write('decryptFailed: $decryptFailed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    senderId,
    isMine,
    createdAt,
    messageType,
    $driftBlobEquality.hash(plaintextEnc),
    decryptFailed,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalMessage &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.senderId == this.senderId &&
          other.isMine == this.isMine &&
          other.createdAt == this.createdAt &&
          other.messageType == this.messageType &&
          $driftBlobEquality.equals(other.plaintextEnc, this.plaintextEnc) &&
          other.decryptFailed == this.decryptFailed);
}

class LocalMessagesCompanion extends UpdateCompanion<LocalMessage> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<String> senderId;
  final Value<bool> isMine;
  final Value<DateTime> createdAt;
  final Value<String> messageType;
  final Value<Uint8List?> plaintextEnc;
  final Value<bool> decryptFailed;
  final Value<int> rowid;
  const LocalMessagesCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.isMine = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.messageType = const Value.absent(),
    this.plaintextEnc = const Value.absent(),
    this.decryptFailed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalMessagesCompanion.insert({
    required String id,
    required String conversationId,
    required String senderId,
    required bool isMine,
    required DateTime createdAt,
    required String messageType,
    this.plaintextEnc = const Value.absent(),
    this.decryptFailed = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       conversationId = Value(conversationId),
       senderId = Value(senderId),
       isMine = Value(isMine),
       createdAt = Value(createdAt),
       messageType = Value(messageType);
  static Insertable<LocalMessage> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? senderId,
    Expression<bool>? isMine,
    Expression<DateTime>? createdAt,
    Expression<String>? messageType,
    Expression<Uint8List>? plaintextEnc,
    Expression<bool>? decryptFailed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (senderId != null) 'sender_id': senderId,
      if (isMine != null) 'is_mine': isMine,
      if (createdAt != null) 'created_at': createdAt,
      if (messageType != null) 'message_type': messageType,
      if (plaintextEnc != null) 'plaintext_enc': plaintextEnc,
      if (decryptFailed != null) 'decrypt_failed': decryptFailed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalMessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? conversationId,
    Value<String>? senderId,
    Value<bool>? isMine,
    Value<DateTime>? createdAt,
    Value<String>? messageType,
    Value<Uint8List?>? plaintextEnc,
    Value<bool>? decryptFailed,
    Value<int>? rowid,
  }) {
    return LocalMessagesCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      isMine: isMine ?? this.isMine,
      createdAt: createdAt ?? this.createdAt,
      messageType: messageType ?? this.messageType,
      plaintextEnc: plaintextEnc ?? this.plaintextEnc,
      decryptFailed: decryptFailed ?? this.decryptFailed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (isMine.present) {
      map['is_mine'] = Variable<bool>(isMine.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (messageType.present) {
      map['message_type'] = Variable<String>(messageType.value);
    }
    if (plaintextEnc.present) {
      map['plaintext_enc'] = Variable<Uint8List>(plaintextEnc.value);
    }
    if (decryptFailed.present) {
      map['decrypt_failed'] = Variable<bool>(decryptFailed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalMessagesCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('isMine: $isMine, ')
          ..write('createdAt: $createdAt, ')
          ..write('messageType: $messageType, ')
          ..write('plaintextEnc: $plaintextEnc, ')
          ..write('decryptFailed: $decryptFailed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedMediaTable extends CachedMedia
    with TableInfo<$CachedMediaTable, CachedMediaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedMediaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _storagePathMeta = const VerificationMeta(
    'storagePath',
  );
  @override
  late final GeneratedColumn<String> storagePath = GeneratedColumn<String>(
    'storage_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _plaintextEncMeta = const VerificationMeta(
    'plaintextEnc',
  );
  @override
  late final GeneratedColumn<Uint8List> plaintextEnc =
      GeneratedColumn<Uint8List>(
        'plaintext_enc',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    storagePath,
    plaintextEnc,
    mimeType,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_media';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedMediaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('storage_path')) {
      context.handle(
        _storagePathMeta,
        storagePath.isAcceptableOrUnknown(
          data['storage_path']!,
          _storagePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_storagePathMeta);
    }
    if (data.containsKey('plaintext_enc')) {
      context.handle(
        _plaintextEncMeta,
        plaintextEnc.isAcceptableOrUnknown(
          data['plaintext_enc']!,
          _plaintextEncMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_plaintextEncMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {storagePath};
  @override
  CachedMediaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedMediaData(
      storagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}storage_path'],
      )!,
      plaintextEnc: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}plaintext_enc'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedMediaTable createAlias(String alias) {
    return $CachedMediaTable(attachedDatabase, alias);
  }
}

class CachedMediaData extends DataClass implements Insertable<CachedMediaData> {
  final String storagePath;
  final Uint8List plaintextEnc;
  final String mimeType;
  final DateTime cachedAt;
  const CachedMediaData({
    required this.storagePath,
    required this.plaintextEnc,
    required this.mimeType,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['storage_path'] = Variable<String>(storagePath);
    map['plaintext_enc'] = Variable<Uint8List>(plaintextEnc);
    map['mime_type'] = Variable<String>(mimeType);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedMediaCompanion toCompanion(bool nullToAbsent) {
    return CachedMediaCompanion(
      storagePath: Value(storagePath),
      plaintextEnc: Value(plaintextEnc),
      mimeType: Value(mimeType),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedMediaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedMediaData(
      storagePath: serializer.fromJson<String>(json['storagePath']),
      plaintextEnc: serializer.fromJson<Uint8List>(json['plaintextEnc']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'storagePath': serializer.toJson<String>(storagePath),
      'plaintextEnc': serializer.toJson<Uint8List>(plaintextEnc),
      'mimeType': serializer.toJson<String>(mimeType),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedMediaData copyWith({
    String? storagePath,
    Uint8List? plaintextEnc,
    String? mimeType,
    DateTime? cachedAt,
  }) => CachedMediaData(
    storagePath: storagePath ?? this.storagePath,
    plaintextEnc: plaintextEnc ?? this.plaintextEnc,
    mimeType: mimeType ?? this.mimeType,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedMediaData copyWithCompanion(CachedMediaCompanion data) {
    return CachedMediaData(
      storagePath: data.storagePath.present
          ? data.storagePath.value
          : this.storagePath,
      plaintextEnc: data.plaintextEnc.present
          ? data.plaintextEnc.value
          : this.plaintextEnc,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedMediaData(')
          ..write('storagePath: $storagePath, ')
          ..write('plaintextEnc: $plaintextEnc, ')
          ..write('mimeType: $mimeType, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    storagePath,
    $driftBlobEquality.hash(plaintextEnc),
    mimeType,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedMediaData &&
          other.storagePath == this.storagePath &&
          $driftBlobEquality.equals(other.plaintextEnc, this.plaintextEnc) &&
          other.mimeType == this.mimeType &&
          other.cachedAt == this.cachedAt);
}

class CachedMediaCompanion extends UpdateCompanion<CachedMediaData> {
  final Value<String> storagePath;
  final Value<Uint8List> plaintextEnc;
  final Value<String> mimeType;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedMediaCompanion({
    this.storagePath = const Value.absent(),
    this.plaintextEnc = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedMediaCompanion.insert({
    required String storagePath,
    required Uint8List plaintextEnc,
    required String mimeType,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : storagePath = Value(storagePath),
       plaintextEnc = Value(plaintextEnc),
       mimeType = Value(mimeType),
       cachedAt = Value(cachedAt);
  static Insertable<CachedMediaData> custom({
    Expression<String>? storagePath,
    Expression<Uint8List>? plaintextEnc,
    Expression<String>? mimeType,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (storagePath != null) 'storage_path': storagePath,
      if (plaintextEnc != null) 'plaintext_enc': plaintextEnc,
      if (mimeType != null) 'mime_type': mimeType,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedMediaCompanion copyWith({
    Value<String>? storagePath,
    Value<Uint8List>? plaintextEnc,
    Value<String>? mimeType,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedMediaCompanion(
      storagePath: storagePath ?? this.storagePath,
      plaintextEnc: plaintextEnc ?? this.plaintextEnc,
      mimeType: mimeType ?? this.mimeType,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (storagePath.present) {
      map['storage_path'] = Variable<String>(storagePath.value);
    }
    if (plaintextEnc.present) {
      map['plaintext_enc'] = Variable<Uint8List>(plaintextEnc.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedMediaCompanion(')
          ..write('storagePath: $storagePath, ')
          ..write('plaintextEnc: $plaintextEnc, ')
          ..write('mimeType: $mimeType, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$SignalDatabase extends GeneratedDatabase {
  _$SignalDatabase(QueryExecutor e) : super(e);
  $SignalDatabaseManager get managers => $SignalDatabaseManager(this);
  late final $LocalIdentitiesTable localIdentities = $LocalIdentitiesTable(
    this,
  );
  late final $PreKeysTable preKeys = $PreKeysTable(this);
  late final $SignedPreKeysTable signedPreKeys = $SignedPreKeysTable(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $TrustedIdentitiesTable trustedIdentities =
      $TrustedIdentitiesTable(this);
  late final $LocalMessagesTable localMessages = $LocalMessagesTable(this);
  late final $CachedMediaTable cachedMedia = $CachedMediaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localIdentities,
    preKeys,
    signedPreKeys,
    sessions,
    trustedIdentities,
    localMessages,
    cachedMedia,
  ];
}

typedef $$LocalIdentitiesTableCreateCompanionBuilder =
    LocalIdentitiesCompanion Function({
      Value<int> id,
      required Uint8List identityKeyPairEnc,
      required int registrationId,
    });
typedef $$LocalIdentitiesTableUpdateCompanionBuilder =
    LocalIdentitiesCompanion Function({
      Value<int> id,
      Value<Uint8List> identityKeyPairEnc,
      Value<int> registrationId,
    });

class $$LocalIdentitiesTableFilterComposer
    extends Composer<_$SignalDatabase, $LocalIdentitiesTable> {
  $$LocalIdentitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get identityKeyPairEnc => $composableBuilder(
    column: $table.identityKeyPairEnc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get registrationId => $composableBuilder(
    column: $table.registrationId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalIdentitiesTableOrderingComposer
    extends Composer<_$SignalDatabase, $LocalIdentitiesTable> {
  $$LocalIdentitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get identityKeyPairEnc => $composableBuilder(
    column: $table.identityKeyPairEnc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get registrationId => $composableBuilder(
    column: $table.registrationId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalIdentitiesTableAnnotationComposer
    extends Composer<_$SignalDatabase, $LocalIdentitiesTable> {
  $$LocalIdentitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<Uint8List> get identityKeyPairEnc => $composableBuilder(
    column: $table.identityKeyPairEnc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get registrationId => $composableBuilder(
    column: $table.registrationId,
    builder: (column) => column,
  );
}

class $$LocalIdentitiesTableTableManager
    extends
        RootTableManager<
          _$SignalDatabase,
          $LocalIdentitiesTable,
          LocalIdentity,
          $$LocalIdentitiesTableFilterComposer,
          $$LocalIdentitiesTableOrderingComposer,
          $$LocalIdentitiesTableAnnotationComposer,
          $$LocalIdentitiesTableCreateCompanionBuilder,
          $$LocalIdentitiesTableUpdateCompanionBuilder,
          (
            LocalIdentity,
            BaseReferences<
              _$SignalDatabase,
              $LocalIdentitiesTable,
              LocalIdentity
            >,
          ),
          LocalIdentity,
          PrefetchHooks Function()
        > {
  $$LocalIdentitiesTableTableManager(
    _$SignalDatabase db,
    $LocalIdentitiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalIdentitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalIdentitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalIdentitiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<Uint8List> identityKeyPairEnc = const Value.absent(),
                Value<int> registrationId = const Value.absent(),
              }) => LocalIdentitiesCompanion(
                id: id,
                identityKeyPairEnc: identityKeyPairEnc,
                registrationId: registrationId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required Uint8List identityKeyPairEnc,
                required int registrationId,
              }) => LocalIdentitiesCompanion.insert(
                id: id,
                identityKeyPairEnc: identityKeyPairEnc,
                registrationId: registrationId,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalIdentitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$SignalDatabase,
      $LocalIdentitiesTable,
      LocalIdentity,
      $$LocalIdentitiesTableFilterComposer,
      $$LocalIdentitiesTableOrderingComposer,
      $$LocalIdentitiesTableAnnotationComposer,
      $$LocalIdentitiesTableCreateCompanionBuilder,
      $$LocalIdentitiesTableUpdateCompanionBuilder,
      (
        LocalIdentity,
        BaseReferences<_$SignalDatabase, $LocalIdentitiesTable, LocalIdentity>,
      ),
      LocalIdentity,
      PrefetchHooks Function()
    >;
typedef $$PreKeysTableCreateCompanionBuilder =
    PreKeysCompanion Function({Value<int> keyId, required Uint8List recordEnc});
typedef $$PreKeysTableUpdateCompanionBuilder =
    PreKeysCompanion Function({Value<int> keyId, Value<Uint8List> recordEnc});

class $$PreKeysTableFilterComposer
    extends Composer<_$SignalDatabase, $PreKeysTable> {
  $$PreKeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get keyId => $composableBuilder(
    column: $table.keyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get recordEnc => $composableBuilder(
    column: $table.recordEnc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PreKeysTableOrderingComposer
    extends Composer<_$SignalDatabase, $PreKeysTable> {
  $$PreKeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get keyId => $composableBuilder(
    column: $table.keyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get recordEnc => $composableBuilder(
    column: $table.recordEnc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PreKeysTableAnnotationComposer
    extends Composer<_$SignalDatabase, $PreKeysTable> {
  $$PreKeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get keyId =>
      $composableBuilder(column: $table.keyId, builder: (column) => column);

  GeneratedColumn<Uint8List> get recordEnc =>
      $composableBuilder(column: $table.recordEnc, builder: (column) => column);
}

class $$PreKeysTableTableManager
    extends
        RootTableManager<
          _$SignalDatabase,
          $PreKeysTable,
          PreKey,
          $$PreKeysTableFilterComposer,
          $$PreKeysTableOrderingComposer,
          $$PreKeysTableAnnotationComposer,
          $$PreKeysTableCreateCompanionBuilder,
          $$PreKeysTableUpdateCompanionBuilder,
          (PreKey, BaseReferences<_$SignalDatabase, $PreKeysTable, PreKey>),
          PreKey,
          PrefetchHooks Function()
        > {
  $$PreKeysTableTableManager(_$SignalDatabase db, $PreKeysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PreKeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PreKeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PreKeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> keyId = const Value.absent(),
                Value<Uint8List> recordEnc = const Value.absent(),
              }) => PreKeysCompanion(keyId: keyId, recordEnc: recordEnc),
          createCompanionCallback:
              ({
                Value<int> keyId = const Value.absent(),
                required Uint8List recordEnc,
              }) => PreKeysCompanion.insert(keyId: keyId, recordEnc: recordEnc),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PreKeysTableProcessedTableManager =
    ProcessedTableManager<
      _$SignalDatabase,
      $PreKeysTable,
      PreKey,
      $$PreKeysTableFilterComposer,
      $$PreKeysTableOrderingComposer,
      $$PreKeysTableAnnotationComposer,
      $$PreKeysTableCreateCompanionBuilder,
      $$PreKeysTableUpdateCompanionBuilder,
      (PreKey, BaseReferences<_$SignalDatabase, $PreKeysTable, PreKey>),
      PreKey,
      PrefetchHooks Function()
    >;
typedef $$SignedPreKeysTableCreateCompanionBuilder =
    SignedPreKeysCompanion Function({
      Value<int> keyId,
      required Uint8List recordEnc,
    });
typedef $$SignedPreKeysTableUpdateCompanionBuilder =
    SignedPreKeysCompanion Function({
      Value<int> keyId,
      Value<Uint8List> recordEnc,
    });

class $$SignedPreKeysTableFilterComposer
    extends Composer<_$SignalDatabase, $SignedPreKeysTable> {
  $$SignedPreKeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get keyId => $composableBuilder(
    column: $table.keyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get recordEnc => $composableBuilder(
    column: $table.recordEnc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SignedPreKeysTableOrderingComposer
    extends Composer<_$SignalDatabase, $SignedPreKeysTable> {
  $$SignedPreKeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get keyId => $composableBuilder(
    column: $table.keyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get recordEnc => $composableBuilder(
    column: $table.recordEnc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SignedPreKeysTableAnnotationComposer
    extends Composer<_$SignalDatabase, $SignedPreKeysTable> {
  $$SignedPreKeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get keyId =>
      $composableBuilder(column: $table.keyId, builder: (column) => column);

  GeneratedColumn<Uint8List> get recordEnc =>
      $composableBuilder(column: $table.recordEnc, builder: (column) => column);
}

class $$SignedPreKeysTableTableManager
    extends
        RootTableManager<
          _$SignalDatabase,
          $SignedPreKeysTable,
          SignedPreKey,
          $$SignedPreKeysTableFilterComposer,
          $$SignedPreKeysTableOrderingComposer,
          $$SignedPreKeysTableAnnotationComposer,
          $$SignedPreKeysTableCreateCompanionBuilder,
          $$SignedPreKeysTableUpdateCompanionBuilder,
          (
            SignedPreKey,
            BaseReferences<_$SignalDatabase, $SignedPreKeysTable, SignedPreKey>,
          ),
          SignedPreKey,
          PrefetchHooks Function()
        > {
  $$SignedPreKeysTableTableManager(
    _$SignalDatabase db,
    $SignedPreKeysTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SignedPreKeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SignedPreKeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SignedPreKeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> keyId = const Value.absent(),
                Value<Uint8List> recordEnc = const Value.absent(),
              }) => SignedPreKeysCompanion(keyId: keyId, recordEnc: recordEnc),
          createCompanionCallback:
              ({
                Value<int> keyId = const Value.absent(),
                required Uint8List recordEnc,
              }) => SignedPreKeysCompanion.insert(
                keyId: keyId,
                recordEnc: recordEnc,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SignedPreKeysTableProcessedTableManager =
    ProcessedTableManager<
      _$SignalDatabase,
      $SignedPreKeysTable,
      SignedPreKey,
      $$SignedPreKeysTableFilterComposer,
      $$SignedPreKeysTableOrderingComposer,
      $$SignedPreKeysTableAnnotationComposer,
      $$SignedPreKeysTableCreateCompanionBuilder,
      $$SignedPreKeysTableUpdateCompanionBuilder,
      (
        SignedPreKey,
        BaseReferences<_$SignalDatabase, $SignedPreKeysTable, SignedPreKey>,
      ),
      SignedPreKey,
      PrefetchHooks Function()
    >;
typedef $$SessionsTableCreateCompanionBuilder =
    SessionsCompanion Function({
      required String address,
      required Uint8List recordEnc,
      Value<int> rowid,
    });
typedef $$SessionsTableUpdateCompanionBuilder =
    SessionsCompanion Function({
      Value<String> address,
      Value<Uint8List> recordEnc,
      Value<int> rowid,
    });

class $$SessionsTableFilterComposer
    extends Composer<_$SignalDatabase, $SessionsTable> {
  $$SessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get recordEnc => $composableBuilder(
    column: $table.recordEnc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SessionsTableOrderingComposer
    extends Composer<_$SignalDatabase, $SessionsTable> {
  $$SessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get recordEnc => $composableBuilder(
    column: $table.recordEnc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$SignalDatabase, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<Uint8List> get recordEnc =>
      $composableBuilder(column: $table.recordEnc, builder: (column) => column);
}

class $$SessionsTableTableManager
    extends
        RootTableManager<
          _$SignalDatabase,
          $SessionsTable,
          Session,
          $$SessionsTableFilterComposer,
          $$SessionsTableOrderingComposer,
          $$SessionsTableAnnotationComposer,
          $$SessionsTableCreateCompanionBuilder,
          $$SessionsTableUpdateCompanionBuilder,
          (Session, BaseReferences<_$SignalDatabase, $SessionsTable, Session>),
          Session,
          PrefetchHooks Function()
        > {
  $$SessionsTableTableManager(_$SignalDatabase db, $SessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> address = const Value.absent(),
                Value<Uint8List> recordEnc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(
                address: address,
                recordEnc: recordEnc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String address,
                required Uint8List recordEnc,
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                address: address,
                recordEnc: recordEnc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$SignalDatabase,
      $SessionsTable,
      Session,
      $$SessionsTableFilterComposer,
      $$SessionsTableOrderingComposer,
      $$SessionsTableAnnotationComposer,
      $$SessionsTableCreateCompanionBuilder,
      $$SessionsTableUpdateCompanionBuilder,
      (Session, BaseReferences<_$SignalDatabase, $SessionsTable, Session>),
      Session,
      PrefetchHooks Function()
    >;
typedef $$TrustedIdentitiesTableCreateCompanionBuilder =
    TrustedIdentitiesCompanion Function({
      required String address,
      required Uint8List identityKeyEnc,
      Value<int> rowid,
    });
typedef $$TrustedIdentitiesTableUpdateCompanionBuilder =
    TrustedIdentitiesCompanion Function({
      Value<String> address,
      Value<Uint8List> identityKeyEnc,
      Value<int> rowid,
    });

class $$TrustedIdentitiesTableFilterComposer
    extends Composer<_$SignalDatabase, $TrustedIdentitiesTable> {
  $$TrustedIdentitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get identityKeyEnc => $composableBuilder(
    column: $table.identityKeyEnc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TrustedIdentitiesTableOrderingComposer
    extends Composer<_$SignalDatabase, $TrustedIdentitiesTable> {
  $$TrustedIdentitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get identityKeyEnc => $composableBuilder(
    column: $table.identityKeyEnc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TrustedIdentitiesTableAnnotationComposer
    extends Composer<_$SignalDatabase, $TrustedIdentitiesTable> {
  $$TrustedIdentitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<Uint8List> get identityKeyEnc => $composableBuilder(
    column: $table.identityKeyEnc,
    builder: (column) => column,
  );
}

class $$TrustedIdentitiesTableTableManager
    extends
        RootTableManager<
          _$SignalDatabase,
          $TrustedIdentitiesTable,
          TrustedIdentity,
          $$TrustedIdentitiesTableFilterComposer,
          $$TrustedIdentitiesTableOrderingComposer,
          $$TrustedIdentitiesTableAnnotationComposer,
          $$TrustedIdentitiesTableCreateCompanionBuilder,
          $$TrustedIdentitiesTableUpdateCompanionBuilder,
          (
            TrustedIdentity,
            BaseReferences<
              _$SignalDatabase,
              $TrustedIdentitiesTable,
              TrustedIdentity
            >,
          ),
          TrustedIdentity,
          PrefetchHooks Function()
        > {
  $$TrustedIdentitiesTableTableManager(
    _$SignalDatabase db,
    $TrustedIdentitiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrustedIdentitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrustedIdentitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrustedIdentitiesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> address = const Value.absent(),
                Value<Uint8List> identityKeyEnc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrustedIdentitiesCompanion(
                address: address,
                identityKeyEnc: identityKeyEnc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String address,
                required Uint8List identityKeyEnc,
                Value<int> rowid = const Value.absent(),
              }) => TrustedIdentitiesCompanion.insert(
                address: address,
                identityKeyEnc: identityKeyEnc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TrustedIdentitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$SignalDatabase,
      $TrustedIdentitiesTable,
      TrustedIdentity,
      $$TrustedIdentitiesTableFilterComposer,
      $$TrustedIdentitiesTableOrderingComposer,
      $$TrustedIdentitiesTableAnnotationComposer,
      $$TrustedIdentitiesTableCreateCompanionBuilder,
      $$TrustedIdentitiesTableUpdateCompanionBuilder,
      (
        TrustedIdentity,
        BaseReferences<
          _$SignalDatabase,
          $TrustedIdentitiesTable,
          TrustedIdentity
        >,
      ),
      TrustedIdentity,
      PrefetchHooks Function()
    >;
typedef $$LocalMessagesTableCreateCompanionBuilder =
    LocalMessagesCompanion Function({
      required String id,
      required String conversationId,
      required String senderId,
      required bool isMine,
      required DateTime createdAt,
      required String messageType,
      Value<Uint8List?> plaintextEnc,
      Value<bool> decryptFailed,
      Value<int> rowid,
    });
typedef $$LocalMessagesTableUpdateCompanionBuilder =
    LocalMessagesCompanion Function({
      Value<String> id,
      Value<String> conversationId,
      Value<String> senderId,
      Value<bool> isMine,
      Value<DateTime> createdAt,
      Value<String> messageType,
      Value<Uint8List?> plaintextEnc,
      Value<bool> decryptFailed,
      Value<int> rowid,
    });

class $$LocalMessagesTableFilterComposer
    extends Composer<_$SignalDatabase, $LocalMessagesTable> {
  $$LocalMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isMine => $composableBuilder(
    column: $table.isMine,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageType => $composableBuilder(
    column: $table.messageType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get plaintextEnc => $composableBuilder(
    column: $table.plaintextEnc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get decryptFailed => $composableBuilder(
    column: $table.decryptFailed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalMessagesTableOrderingComposer
    extends Composer<_$SignalDatabase, $LocalMessagesTable> {
  $$LocalMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isMine => $composableBuilder(
    column: $table.isMine,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageType => $composableBuilder(
    column: $table.messageType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get plaintextEnc => $composableBuilder(
    column: $table.plaintextEnc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get decryptFailed => $composableBuilder(
    column: $table.decryptFailed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalMessagesTableAnnotationComposer
    extends Composer<_$SignalDatabase, $LocalMessagesTable> {
  $$LocalMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<bool> get isMine =>
      $composableBuilder(column: $table.isMine, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get messageType => $composableBuilder(
    column: $table.messageType,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get plaintextEnc => $composableBuilder(
    column: $table.plaintextEnc,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get decryptFailed => $composableBuilder(
    column: $table.decryptFailed,
    builder: (column) => column,
  );
}

class $$LocalMessagesTableTableManager
    extends
        RootTableManager<
          _$SignalDatabase,
          $LocalMessagesTable,
          LocalMessage,
          $$LocalMessagesTableFilterComposer,
          $$LocalMessagesTableOrderingComposer,
          $$LocalMessagesTableAnnotationComposer,
          $$LocalMessagesTableCreateCompanionBuilder,
          $$LocalMessagesTableUpdateCompanionBuilder,
          (
            LocalMessage,
            BaseReferences<_$SignalDatabase, $LocalMessagesTable, LocalMessage>,
          ),
          LocalMessage,
          PrefetchHooks Function()
        > {
  $$LocalMessagesTableTableManager(
    _$SignalDatabase db,
    $LocalMessagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> senderId = const Value.absent(),
                Value<bool> isMine = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> messageType = const Value.absent(),
                Value<Uint8List?> plaintextEnc = const Value.absent(),
                Value<bool> decryptFailed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalMessagesCompanion(
                id: id,
                conversationId: conversationId,
                senderId: senderId,
                isMine: isMine,
                createdAt: createdAt,
                messageType: messageType,
                plaintextEnc: plaintextEnc,
                decryptFailed: decryptFailed,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String conversationId,
                required String senderId,
                required bool isMine,
                required DateTime createdAt,
                required String messageType,
                Value<Uint8List?> plaintextEnc = const Value.absent(),
                Value<bool> decryptFailed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalMessagesCompanion.insert(
                id: id,
                conversationId: conversationId,
                senderId: senderId,
                isMine: isMine,
                createdAt: createdAt,
                messageType: messageType,
                plaintextEnc: plaintextEnc,
                decryptFailed: decryptFailed,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$SignalDatabase,
      $LocalMessagesTable,
      LocalMessage,
      $$LocalMessagesTableFilterComposer,
      $$LocalMessagesTableOrderingComposer,
      $$LocalMessagesTableAnnotationComposer,
      $$LocalMessagesTableCreateCompanionBuilder,
      $$LocalMessagesTableUpdateCompanionBuilder,
      (
        LocalMessage,
        BaseReferences<_$SignalDatabase, $LocalMessagesTable, LocalMessage>,
      ),
      LocalMessage,
      PrefetchHooks Function()
    >;
typedef $$CachedMediaTableCreateCompanionBuilder =
    CachedMediaCompanion Function({
      required String storagePath,
      required Uint8List plaintextEnc,
      required String mimeType,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedMediaTableUpdateCompanionBuilder =
    CachedMediaCompanion Function({
      Value<String> storagePath,
      Value<Uint8List> plaintextEnc,
      Value<String> mimeType,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedMediaTableFilterComposer
    extends Composer<_$SignalDatabase, $CachedMediaTable> {
  $$CachedMediaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get plaintextEnc => $composableBuilder(
    column: $table.plaintextEnc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedMediaTableOrderingComposer
    extends Composer<_$SignalDatabase, $CachedMediaTable> {
  $$CachedMediaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get plaintextEnc => $composableBuilder(
    column: $table.plaintextEnc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedMediaTableAnnotationComposer
    extends Composer<_$SignalDatabase, $CachedMediaTable> {
  $$CachedMediaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get plaintextEnc => $composableBuilder(
    column: $table.plaintextEnc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedMediaTableTableManager
    extends
        RootTableManager<
          _$SignalDatabase,
          $CachedMediaTable,
          CachedMediaData,
          $$CachedMediaTableFilterComposer,
          $$CachedMediaTableOrderingComposer,
          $$CachedMediaTableAnnotationComposer,
          $$CachedMediaTableCreateCompanionBuilder,
          $$CachedMediaTableUpdateCompanionBuilder,
          (
            CachedMediaData,
            BaseReferences<
              _$SignalDatabase,
              $CachedMediaTable,
              CachedMediaData
            >,
          ),
          CachedMediaData,
          PrefetchHooks Function()
        > {
  $$CachedMediaTableTableManager(_$SignalDatabase db, $CachedMediaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedMediaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedMediaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedMediaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> storagePath = const Value.absent(),
                Value<Uint8List> plaintextEnc = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMediaCompanion(
                storagePath: storagePath,
                plaintextEnc: plaintextEnc,
                mimeType: mimeType,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String storagePath,
                required Uint8List plaintextEnc,
                required String mimeType,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedMediaCompanion.insert(
                storagePath: storagePath,
                plaintextEnc: plaintextEnc,
                mimeType: mimeType,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedMediaTableProcessedTableManager =
    ProcessedTableManager<
      _$SignalDatabase,
      $CachedMediaTable,
      CachedMediaData,
      $$CachedMediaTableFilterComposer,
      $$CachedMediaTableOrderingComposer,
      $$CachedMediaTableAnnotationComposer,
      $$CachedMediaTableCreateCompanionBuilder,
      $$CachedMediaTableUpdateCompanionBuilder,
      (
        CachedMediaData,
        BaseReferences<_$SignalDatabase, $CachedMediaTable, CachedMediaData>,
      ),
      CachedMediaData,
      PrefetchHooks Function()
    >;

class $SignalDatabaseManager {
  final _$SignalDatabase _db;
  $SignalDatabaseManager(this._db);
  $$LocalIdentitiesTableTableManager get localIdentities =>
      $$LocalIdentitiesTableTableManager(_db, _db.localIdentities);
  $$PreKeysTableTableManager get preKeys =>
      $$PreKeysTableTableManager(_db, _db.preKeys);
  $$SignedPreKeysTableTableManager get signedPreKeys =>
      $$SignedPreKeysTableTableManager(_db, _db.signedPreKeys);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$TrustedIdentitiesTableTableManager get trustedIdentities =>
      $$TrustedIdentitiesTableTableManager(_db, _db.trustedIdentities);
  $$LocalMessagesTableTableManager get localMessages =>
      $$LocalMessagesTableTableManager(_db, _db.localMessages);
  $$CachedMediaTableTableManager get cachedMedia =>
      $$CachedMediaTableTableManager(_db, _db.cachedMedia);
}
