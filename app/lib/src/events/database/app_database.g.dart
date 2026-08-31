// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $EventsTable extends Events with TableInfo<$EventsTable, Event> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gameIdMeta = const VerificationMeta('gameId');
  @override
  late final GeneratedColumn<String> gameId = GeneratedColumn<String>(
    'game_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wallClockMeta = const VerificationMeta(
    'wallClock',
  );
  @override
  late final GeneratedColumn<DateTime> wallClock = GeneratedColumn<DateTime>(
    'wall_clock',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _correctsMeta = const VerificationMeta(
    'corrects',
  );
  @override
  late final GeneratedColumn<String> corrects = GeneratedColumn<String>(
    'corrects',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _effectiveAfterMeta = const VerificationMeta(
    'effectiveAfter',
  );
  @override
  late final GeneratedColumn<String> effectiveAfter = GeneratedColumn<String>(
    'effective_after',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    gameId,
    seq,
    deviceId,
    createdBy,
    wallClock,
    type,
    payload,
    corrects,
    effectiveAfter,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'events';
  @override
  VerificationContext validateIntegrity(
    Insertable<Event> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('game_id')) {
      context.handle(
        _gameIdMeta,
        gameId.isAcceptableOrUnknown(data['game_id']!, _gameIdMeta),
      );
    } else if (isInserting) {
      context.missing(_gameIdMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    } else if (isInserting) {
      context.missing(_createdByMeta);
    }
    if (data.containsKey('wall_clock')) {
      context.handle(
        _wallClockMeta,
        wallClock.isAcceptableOrUnknown(data['wall_clock']!, _wallClockMeta),
      );
    } else if (isInserting) {
      context.missing(_wallClockMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('corrects')) {
      context.handle(
        _correctsMeta,
        corrects.isAcceptableOrUnknown(data['corrects']!, _correctsMeta),
      );
    }
    if (data.containsKey('effective_after')) {
      context.handle(
        _effectiveAfterMeta,
        effectiveAfter.isAcceptableOrUnknown(
          data['effective_after']!,
          _effectiveAfterMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Event map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Event(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      gameId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}game_id'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      )!,
      wallClock: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}wall_clock'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      corrects: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}corrects'],
      ),
      effectiveAfter: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}effective_after'],
      ),
    );
  }

  @override
  $EventsTable createAlias(String alias) {
    return $EventsTable(attachedDatabase, alias);
  }
}

class Event extends DataClass implements Insertable<Event> {
  final String id;
  final String gameId;
  final int seq;
  final String deviceId;
  final String createdBy;
  final DateTime wallClock;
  final String type;
  final String payload;
  final String? corrects;
  final String? effectiveAfter;
  const Event({
    required this.id,
    required this.gameId,
    required this.seq,
    required this.deviceId,
    required this.createdBy,
    required this.wallClock,
    required this.type,
    required this.payload,
    this.corrects,
    this.effectiveAfter,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['game_id'] = Variable<String>(gameId);
    map['seq'] = Variable<int>(seq);
    map['device_id'] = Variable<String>(deviceId);
    map['created_by'] = Variable<String>(createdBy);
    map['wall_clock'] = Variable<DateTime>(wallClock);
    map['type'] = Variable<String>(type);
    map['payload'] = Variable<String>(payload);
    if (!nullToAbsent || corrects != null) {
      map['corrects'] = Variable<String>(corrects);
    }
    if (!nullToAbsent || effectiveAfter != null) {
      map['effective_after'] = Variable<String>(effectiveAfter);
    }
    return map;
  }

  EventsCompanion toCompanion(bool nullToAbsent) {
    return EventsCompanion(
      id: Value(id),
      gameId: Value(gameId),
      seq: Value(seq),
      deviceId: Value(deviceId),
      createdBy: Value(createdBy),
      wallClock: Value(wallClock),
      type: Value(type),
      payload: Value(payload),
      corrects: corrects == null && nullToAbsent
          ? const Value.absent()
          : Value(corrects),
      effectiveAfter: effectiveAfter == null && nullToAbsent
          ? const Value.absent()
          : Value(effectiveAfter),
    );
  }

  factory Event.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Event(
      id: serializer.fromJson<String>(json['id']),
      gameId: serializer.fromJson<String>(json['gameId']),
      seq: serializer.fromJson<int>(json['seq']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      createdBy: serializer.fromJson<String>(json['createdBy']),
      wallClock: serializer.fromJson<DateTime>(json['wallClock']),
      type: serializer.fromJson<String>(json['type']),
      payload: serializer.fromJson<String>(json['payload']),
      corrects: serializer.fromJson<String?>(json['corrects']),
      effectiveAfter: serializer.fromJson<String?>(json['effectiveAfter']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'gameId': serializer.toJson<String>(gameId),
      'seq': serializer.toJson<int>(seq),
      'deviceId': serializer.toJson<String>(deviceId),
      'createdBy': serializer.toJson<String>(createdBy),
      'wallClock': serializer.toJson<DateTime>(wallClock),
      'type': serializer.toJson<String>(type),
      'payload': serializer.toJson<String>(payload),
      'corrects': serializer.toJson<String?>(corrects),
      'effectiveAfter': serializer.toJson<String?>(effectiveAfter),
    };
  }

  Event copyWith({
    String? id,
    String? gameId,
    int? seq,
    String? deviceId,
    String? createdBy,
    DateTime? wallClock,
    String? type,
    String? payload,
    Value<String?> corrects = const Value.absent(),
    Value<String?> effectiveAfter = const Value.absent(),
  }) => Event(
    id: id ?? this.id,
    gameId: gameId ?? this.gameId,
    seq: seq ?? this.seq,
    deviceId: deviceId ?? this.deviceId,
    createdBy: createdBy ?? this.createdBy,
    wallClock: wallClock ?? this.wallClock,
    type: type ?? this.type,
    payload: payload ?? this.payload,
    corrects: corrects.present ? corrects.value : this.corrects,
    effectiveAfter: effectiveAfter.present
        ? effectiveAfter.value
        : this.effectiveAfter,
  );
  Event copyWithCompanion(EventsCompanion data) {
    return Event(
      id: data.id.present ? data.id.value : this.id,
      gameId: data.gameId.present ? data.gameId.value : this.gameId,
      seq: data.seq.present ? data.seq.value : this.seq,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      wallClock: data.wallClock.present ? data.wallClock.value : this.wallClock,
      type: data.type.present ? data.type.value : this.type,
      payload: data.payload.present ? data.payload.value : this.payload,
      corrects: data.corrects.present ? data.corrects.value : this.corrects,
      effectiveAfter: data.effectiveAfter.present
          ? data.effectiveAfter.value
          : this.effectiveAfter,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Event(')
          ..write('id: $id, ')
          ..write('gameId: $gameId, ')
          ..write('seq: $seq, ')
          ..write('deviceId: $deviceId, ')
          ..write('createdBy: $createdBy, ')
          ..write('wallClock: $wallClock, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('corrects: $corrects, ')
          ..write('effectiveAfter: $effectiveAfter')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    gameId,
    seq,
    deviceId,
    createdBy,
    wallClock,
    type,
    payload,
    corrects,
    effectiveAfter,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Event &&
          other.id == this.id &&
          other.gameId == this.gameId &&
          other.seq == this.seq &&
          other.deviceId == this.deviceId &&
          other.createdBy == this.createdBy &&
          other.wallClock == this.wallClock &&
          other.type == this.type &&
          other.payload == this.payload &&
          other.corrects == this.corrects &&
          other.effectiveAfter == this.effectiveAfter);
}

class EventsCompanion extends UpdateCompanion<Event> {
  final Value<String> id;
  final Value<String> gameId;
  final Value<int> seq;
  final Value<String> deviceId;
  final Value<String> createdBy;
  final Value<DateTime> wallClock;
  final Value<String> type;
  final Value<String> payload;
  final Value<String?> corrects;
  final Value<String?> effectiveAfter;
  final Value<int> rowid;
  const EventsCompanion({
    this.id = const Value.absent(),
    this.gameId = const Value.absent(),
    this.seq = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.wallClock = const Value.absent(),
    this.type = const Value.absent(),
    this.payload = const Value.absent(),
    this.corrects = const Value.absent(),
    this.effectiveAfter = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EventsCompanion.insert({
    required String id,
    required String gameId,
    required int seq,
    required String deviceId,
    required String createdBy,
    required DateTime wallClock,
    required String type,
    required String payload,
    this.corrects = const Value.absent(),
    this.effectiveAfter = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       gameId = Value(gameId),
       seq = Value(seq),
       deviceId = Value(deviceId),
       createdBy = Value(createdBy),
       wallClock = Value(wallClock),
       type = Value(type),
       payload = Value(payload);
  static Insertable<Event> custom({
    Expression<String>? id,
    Expression<String>? gameId,
    Expression<int>? seq,
    Expression<String>? deviceId,
    Expression<String>? createdBy,
    Expression<DateTime>? wallClock,
    Expression<String>? type,
    Expression<String>? payload,
    Expression<String>? corrects,
    Expression<String>? effectiveAfter,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (gameId != null) 'game_id': gameId,
      if (seq != null) 'seq': seq,
      if (deviceId != null) 'device_id': deviceId,
      if (createdBy != null) 'created_by': createdBy,
      if (wallClock != null) 'wall_clock': wallClock,
      if (type != null) 'type': type,
      if (payload != null) 'payload': payload,
      if (corrects != null) 'corrects': corrects,
      if (effectiveAfter != null) 'effective_after': effectiveAfter,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EventsCompanion copyWith({
    Value<String>? id,
    Value<String>? gameId,
    Value<int>? seq,
    Value<String>? deviceId,
    Value<String>? createdBy,
    Value<DateTime>? wallClock,
    Value<String>? type,
    Value<String>? payload,
    Value<String?>? corrects,
    Value<String?>? effectiveAfter,
    Value<int>? rowid,
  }) {
    return EventsCompanion(
      id: id ?? this.id,
      gameId: gameId ?? this.gameId,
      seq: seq ?? this.seq,
      deviceId: deviceId ?? this.deviceId,
      createdBy: createdBy ?? this.createdBy,
      wallClock: wallClock ?? this.wallClock,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      corrects: corrects ?? this.corrects,
      effectiveAfter: effectiveAfter ?? this.effectiveAfter,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (gameId.present) {
      map['game_id'] = Variable<String>(gameId.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (wallClock.present) {
      map['wall_clock'] = Variable<DateTime>(wallClock.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (corrects.present) {
      map['corrects'] = Variable<String>(corrects.value);
    }
    if (effectiveAfter.present) {
      map['effective_after'] = Variable<String>(effectiveAfter.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventsCompanion(')
          ..write('id: $id, ')
          ..write('gameId: $gameId, ')
          ..write('seq: $seq, ')
          ..write('deviceId: $deviceId, ')
          ..write('createdBy: $createdBy, ')
          ..write('wallClock: $wallClock, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('corrects: $corrects, ')
          ..write('effectiveAfter: $effectiveAfter, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlayJournalsTable extends PlayJournals
    with TableInfo<$PlayJournalsTable, PlayJournal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlayJournalsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _gameIdMeta = const VerificationMeta('gameId');
  @override
  late final GeneratedColumn<String> gameId = GeneratedColumn<String>(
    'game_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _draftMeta = const VerificationMeta('draft');
  @override
  late final GeneratedColumn<String> draft = GeneratedColumn<String>(
    'draft',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [gameId, draft];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'play_journals';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlayJournal> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('game_id')) {
      context.handle(
        _gameIdMeta,
        gameId.isAcceptableOrUnknown(data['game_id']!, _gameIdMeta),
      );
    } else if (isInserting) {
      context.missing(_gameIdMeta);
    }
    if (data.containsKey('draft')) {
      context.handle(
        _draftMeta,
        draft.isAcceptableOrUnknown(data['draft']!, _draftMeta),
      );
    } else if (isInserting) {
      context.missing(_draftMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {gameId};
  @override
  PlayJournal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlayJournal(
      gameId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}game_id'],
      )!,
      draft: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}draft'],
      )!,
    );
  }

  @override
  $PlayJournalsTable createAlias(String alias) {
    return $PlayJournalsTable(attachedDatabase, alias);
  }
}

class PlayJournal extends DataClass implements Insertable<PlayJournal> {
  final String gameId;
  final String draft;
  const PlayJournal({required this.gameId, required this.draft});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['game_id'] = Variable<String>(gameId);
    map['draft'] = Variable<String>(draft);
    return map;
  }

  PlayJournalsCompanion toCompanion(bool nullToAbsent) {
    return PlayJournalsCompanion(gameId: Value(gameId), draft: Value(draft));
  }

  factory PlayJournal.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlayJournal(
      gameId: serializer.fromJson<String>(json['gameId']),
      draft: serializer.fromJson<String>(json['draft']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'gameId': serializer.toJson<String>(gameId),
      'draft': serializer.toJson<String>(draft),
    };
  }

  PlayJournal copyWith({String? gameId, String? draft}) =>
      PlayJournal(gameId: gameId ?? this.gameId, draft: draft ?? this.draft);
  PlayJournal copyWithCompanion(PlayJournalsCompanion data) {
    return PlayJournal(
      gameId: data.gameId.present ? data.gameId.value : this.gameId,
      draft: data.draft.present ? data.draft.value : this.draft,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlayJournal(')
          ..write('gameId: $gameId, ')
          ..write('draft: $draft')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(gameId, draft);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlayJournal &&
          other.gameId == this.gameId &&
          other.draft == this.draft);
}

class PlayJournalsCompanion extends UpdateCompanion<PlayJournal> {
  final Value<String> gameId;
  final Value<String> draft;
  final Value<int> rowid;
  const PlayJournalsCompanion({
    this.gameId = const Value.absent(),
    this.draft = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlayJournalsCompanion.insert({
    required String gameId,
    required String draft,
    this.rowid = const Value.absent(),
  }) : gameId = Value(gameId),
       draft = Value(draft);
  static Insertable<PlayJournal> custom({
    Expression<String>? gameId,
    Expression<String>? draft,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (gameId != null) 'game_id': gameId,
      if (draft != null) 'draft': draft,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlayJournalsCompanion copyWith({
    Value<String>? gameId,
    Value<String>? draft,
    Value<int>? rowid,
  }) {
    return PlayJournalsCompanion(
      gameId: gameId ?? this.gameId,
      draft: draft ?? this.draft,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (gameId.present) {
      map['game_id'] = Variable<String>(gameId.value);
    }
    if (draft.present) {
      map['draft'] = Variable<String>(draft.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlayJournalsCompanion(')
          ..write('gameId: $gameId, ')
          ..write('draft: $draft, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSetting copyWith({String? key, String? value}) =>
      AppSetting(key: key ?? this.key, value: value ?? this.value);
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $EventsTable events = $EventsTable(this);
  late final $PlayJournalsTable playJournals = $PlayJournalsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    events,
    playJournals,
    appSettings,
  ];
}

typedef $$EventsTableCreateCompanionBuilder =
    EventsCompanion Function({
      required String id,
      required String gameId,
      required int seq,
      required String deviceId,
      required String createdBy,
      required DateTime wallClock,
      required String type,
      required String payload,
      Value<String?> corrects,
      Value<String?> effectiveAfter,
      Value<int> rowid,
    });
typedef $$EventsTableUpdateCompanionBuilder =
    EventsCompanion Function({
      Value<String> id,
      Value<String> gameId,
      Value<int> seq,
      Value<String> deviceId,
      Value<String> createdBy,
      Value<DateTime> wallClock,
      Value<String> type,
      Value<String> payload,
      Value<String?> corrects,
      Value<String?> effectiveAfter,
      Value<int> rowid,
    });

class $$EventsTableFilterComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableFilterComposer({
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

  ColumnFilters<String> get gameId => $composableBuilder(
    column: $table.gameId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get wallClock => $composableBuilder(
    column: $table.wallClock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get corrects => $composableBuilder(
    column: $table.corrects,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get effectiveAfter => $composableBuilder(
    column: $table.effectiveAfter,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EventsTableOrderingComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableOrderingComposer({
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

  ColumnOrderings<String> get gameId => $composableBuilder(
    column: $table.gameId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get wallClock => $composableBuilder(
    column: $table.wallClock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get corrects => $composableBuilder(
    column: $table.corrects,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get effectiveAfter => $composableBuilder(
    column: $table.effectiveAfter,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get gameId =>
      $composableBuilder(column: $table.gameId, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  GeneratedColumn<DateTime> get wallClock =>
      $composableBuilder(column: $table.wallClock, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get corrects =>
      $composableBuilder(column: $table.corrects, builder: (column) => column);

  GeneratedColumn<String> get effectiveAfter => $composableBuilder(
    column: $table.effectiveAfter,
    builder: (column) => column,
  );
}

class $$EventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventsTable,
          Event,
          $$EventsTableFilterComposer,
          $$EventsTableOrderingComposer,
          $$EventsTableAnnotationComposer,
          $$EventsTableCreateCompanionBuilder,
          $$EventsTableUpdateCompanionBuilder,
          (Event, BaseReferences<_$AppDatabase, $EventsTable, Event>),
          Event,
          PrefetchHooks Function()
        > {
  $$EventsTableTableManager(_$AppDatabase db, $EventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> gameId = const Value.absent(),
                Value<int> seq = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> createdBy = const Value.absent(),
                Value<DateTime> wallClock = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String?> corrects = const Value.absent(),
                Value<String?> effectiveAfter = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventsCompanion(
                id: id,
                gameId: gameId,
                seq: seq,
                deviceId: deviceId,
                createdBy: createdBy,
                wallClock: wallClock,
                type: type,
                payload: payload,
                corrects: corrects,
                effectiveAfter: effectiveAfter,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String gameId,
                required int seq,
                required String deviceId,
                required String createdBy,
                required DateTime wallClock,
                required String type,
                required String payload,
                Value<String?> corrects = const Value.absent(),
                Value<String?> effectiveAfter = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventsCompanion.insert(
                id: id,
                gameId: gameId,
                seq: seq,
                deviceId: deviceId,
                createdBy: createdBy,
                wallClock: wallClock,
                type: type,
                payload: payload,
                corrects: corrects,
                effectiveAfter: effectiveAfter,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventsTable,
      Event,
      $$EventsTableFilterComposer,
      $$EventsTableOrderingComposer,
      $$EventsTableAnnotationComposer,
      $$EventsTableCreateCompanionBuilder,
      $$EventsTableUpdateCompanionBuilder,
      (Event, BaseReferences<_$AppDatabase, $EventsTable, Event>),
      Event,
      PrefetchHooks Function()
    >;
typedef $$PlayJournalsTableCreateCompanionBuilder =
    PlayJournalsCompanion Function({
      required String gameId,
      required String draft,
      Value<int> rowid,
    });
typedef $$PlayJournalsTableUpdateCompanionBuilder =
    PlayJournalsCompanion Function({
      Value<String> gameId,
      Value<String> draft,
      Value<int> rowid,
    });

class $$PlayJournalsTableFilterComposer
    extends Composer<_$AppDatabase, $PlayJournalsTable> {
  $$PlayJournalsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get gameId => $composableBuilder(
    column: $table.gameId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get draft => $composableBuilder(
    column: $table.draft,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlayJournalsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlayJournalsTable> {
  $$PlayJournalsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get gameId => $composableBuilder(
    column: $table.gameId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get draft => $composableBuilder(
    column: $table.draft,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlayJournalsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlayJournalsTable> {
  $$PlayJournalsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get gameId =>
      $composableBuilder(column: $table.gameId, builder: (column) => column);

  GeneratedColumn<String> get draft =>
      $composableBuilder(column: $table.draft, builder: (column) => column);
}

class $$PlayJournalsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlayJournalsTable,
          PlayJournal,
          $$PlayJournalsTableFilterComposer,
          $$PlayJournalsTableOrderingComposer,
          $$PlayJournalsTableAnnotationComposer,
          $$PlayJournalsTableCreateCompanionBuilder,
          $$PlayJournalsTableUpdateCompanionBuilder,
          (
            PlayJournal,
            BaseReferences<_$AppDatabase, $PlayJournalsTable, PlayJournal>,
          ),
          PlayJournal,
          PrefetchHooks Function()
        > {
  $$PlayJournalsTableTableManager(_$AppDatabase db, $PlayJournalsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlayJournalsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlayJournalsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlayJournalsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> gameId = const Value.absent(),
                Value<String> draft = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlayJournalsCompanion(
                gameId: gameId,
                draft: draft,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String gameId,
                required String draft,
                Value<int> rowid = const Value.absent(),
              }) => PlayJournalsCompanion.insert(
                gameId: gameId,
                draft: draft,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlayJournalsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlayJournalsTable,
      PlayJournal,
      $$PlayJournalsTableFilterComposer,
      $$PlayJournalsTableOrderingComposer,
      $$PlayJournalsTableAnnotationComposer,
      $$PlayJournalsTableCreateCompanionBuilder,
      $$PlayJournalsTableUpdateCompanionBuilder,
      (
        PlayJournal,
        BaseReferences<_$AppDatabase, $PlayJournalsTable, PlayJournal>,
      ),
      PlayJournal,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db, _db.events);
  $$PlayJournalsTableTableManager get playJournals =>
      $$PlayJournalsTableTableManager(_db, _db.playJournals);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
}
