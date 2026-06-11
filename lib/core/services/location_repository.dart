import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/location_entity.dart';

class LocationRepository {
  final Logger _logger = Logger();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// Delete only synced rows for a specific day (UTC-based day boundaries).
  Future<int> deleteSyncedForDay(DateTime day) async {
    final db = await _dbHelper.database;

    final startUtc = DateTime.utc(day.year, day.month, day.day);
    final endUtc = startUtc.add(const Duration(days: 1));

    return db.delete(
      DatabaseHelper.tableLocations,
      where:
          '${DatabaseHelper.colIsSynced} = ? AND ${DatabaseHelper.colTimestamp} >= ? AND ${DatabaseHelper.colTimestamp} < ?',
      whereArgs: [1, startUtc.toIso8601String(), endUtc.toIso8601String()],
    );
  }

  Future<void> initialize() async {
    await _dbHelper.database;
    _logger.i('LocationRepository initialized');
  }

  /// Insert a single location.
  Future<int> insert(LocationEntity location) async {
    final db = await _dbHelper.database;
    return db.insert(DatabaseHelper.tableLocations, location.toMap());
  }

  /// Batch insert multiple locations inside a single transaction.
  Future<List<int>> insertBatch(List<LocationEntity> locations) async {
    if (locations.isEmpty) return [];

    final db = await _dbHelper.database;
    final List<int> ids = [];

    await db.transaction((txn) async {
      for (final location in locations) {
        final id = await txn.insert(
          DatabaseHelper.tableLocations,
          location.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        ids.add(id);
      }
    });

    _logger.i('Batch insert: ${locations.length} locations saved');
    return ids;
  }

  /// Get all locations for specific user ordered by timestamp (newest first).
  Future<List<LocationEntity>> getAllByUserId(int userId, {int? limit}) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.tableLocations,
      where: '${DatabaseHelper.colUserId} = ?',
      whereArgs: [userId],
      orderBy: '${DatabaseHelper.colTimestamp} DESC',
      limit: limit,
    );
    return maps.map((m) => LocationEntity.fromMap(m)).toList();
  }

  Future<List<LocationEntity>> getAllBySurveiId({
    required int surveiId,
    int? limit,
  }) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.tableLocations,
      where: '${DatabaseHelper.colSurveiId} = ?',
      whereArgs: [surveiId],
      orderBy: '${DatabaseHelper.colTimestamp} DESC',
      limit: limit,
    );
    return maps.map((m) => LocationEntity.fromMap(m)).toList();
  }

  Future<List<LocationEntity>> getAllBySurveiIdAndUserId({
    required int surveiId,
    required int userId,
    int? limit,
  }) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.tableLocations,
      where:
          '${DatabaseHelper.colSurveiId} = ? AND ${DatabaseHelper.colUserId} = ?',
      whereArgs: [surveiId, userId],
      orderBy: '${DatabaseHelper.colTimestamp} DESC',
      limit: limit,
    );
    return maps.map((m) => LocationEntity.fromMap(m)).toList();
  }

  Future<List<LocationEntity>> getBetween({
    required DateTime start,
    required DateTime end,
    int? userId,
  }) async {
    final db = await _dbHelper.database;
    final whereParts = <String>[
      '${DatabaseHelper.colTimestamp} >= ? AND ${DatabaseHelper.colTimestamp} <= ?',
    ];
    final whereArgs = <Object>[
      start.toUtc().toIso8601String(),
      end.toUtc().toIso8601String(),
    ];

    if (userId != null) {
      whereParts.add('${DatabaseHelper.colUserId} = ?');
      whereArgs.add(userId);
    }

    final whereClause = whereParts.join(' AND ');

    final maps = await db.query(
      DatabaseHelper.tableLocations,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: '${DatabaseHelper.colTimestamp} DESC',
    );
    return maps.map((m) => LocationEntity.fromMap(m)).toList();
  }

  Future<List<LocationEntity>> getBetweenBySurveiId({
    required int surveiId,
    required DateTime start,
    required DateTime end,
    int? userId,
  }) async {
    final db = await _dbHelper.database;
    final whereParts = <String>[
      '${DatabaseHelper.colSurveiId} = ?',
      '${DatabaseHelper.colTimestamp} >= ? AND ${DatabaseHelper.colTimestamp} <= ?',
    ];
    final whereArgs = <Object>[
      surveiId,
      start.toUtc().toIso8601String(),
      end.toUtc().toIso8601String(),
    ];

    if (userId != null) {
      whereParts.add('${DatabaseHelper.colUserId} = ?');
      whereArgs.add(userId);
    }

    final whereClause = whereParts.join(' AND ');

    final maps = await db.query(
      DatabaseHelper.tableLocations,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: '${DatabaseHelper.colTimestamp} DESC',
    );
    return maps.map((m) => LocationEntity.fromMap(m)).toList();
  }

  /// Get locations that haven't been synced to the server yet.
  Future<List<LocationEntity>> getUnsynced({int? limit, int? userId}) async {
    final db = await _dbHelper.database;

    final whereParts = <String>['${DatabaseHelper.colIsSynced} = ?'];
    final whereArgs = <Object>[0];

    if (userId != null) {
      whereParts.add('${DatabaseHelper.colUserId} = ?');
      whereArgs.add(userId);
    }

    final whereClause = whereParts.join(' AND ');

    final maps = await db.query(
      DatabaseHelper.tableLocations,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: '${DatabaseHelper.colTimestamp} ASC',
      limit: limit,
    );
    return maps.map((m) => LocationEntity.fromMap(m)).toList();
  }

  /// Count total unsynced locations.
  Future<int> countUnsynced() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${DatabaseHelper.tableLocations} WHERE ${DatabaseHelper.colIsSynced} = 0',
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Get the most recent location (for distance filter comparison).
  Future<LocationEntity?> getLastLocation() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.tableLocations,
      orderBy: '${DatabaseHelper.colTimestamp} DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return LocationEntity.fromMap(maps.first);
  }

  /// Convert a time-range query directly to a list of LatLng for flutter_map.
  Future<List<LatLng>> getRouteBetween({
    required DateTime start,
    required DateTime end,
  }) async {
    final locations = await getBetween(start: start, end: end);
    return locations.map((l) => l.toLatLng()).toList();
  }

  /// Mark specific locations as synced after successful API upload.
  Future<int> markAsSynced(List<int> ids) async {
    if (ids.isEmpty) return 0;

    final db = await _dbHelper.database;
    final placeholders = List.filled(ids.length, '?').join(',');

    final count = await db.rawUpdate(
      'UPDATE ${DatabaseHelper.tableLocations} '
      'SET ${DatabaseHelper.colIsSynced} = 1 '
      'WHERE ${DatabaseHelper.colId} IN ($placeholders)',
      ids,
    );

    _logger.i('Marked $count locations as synced');
    return count;
  }

  /// Delete all locations (use with caution — mainly for testing).
  Future<int> deleteAll() async {
    final db = await _dbHelper.database;
    return db.delete(DatabaseHelper.tableLocations);
  }

  /// Delete locations for a specific survei.
  Future<int> deleteAllBySurveiId(int surveiId) async {
    final db = await _dbHelper.database;
    return db.delete(
      DatabaseHelper.tableLocations,
      where: '${DatabaseHelper.colSurveiId} = ?',
      whereArgs: [surveiId],
    );
  }

  /// Delete locations older than a certain date.
  Future<int> deleteOlderThan(DateTime date) async {
    final db = await _dbHelper.database;
    return db.delete(
      DatabaseHelper.tableLocations,
      where: '${DatabaseHelper.colTimestamp} < ?',
      whereArgs: [date.toUtc().toIso8601String()],
    );
  }

  /// Delete only synced locations to free up space while keeping unsynced data safe.
  Future<int> deleteSynced() async {
    final db = await _dbHelper.database;
    return db.delete(
      DatabaseHelper.tableLocations,
      where: '${DatabaseHelper.colIsSynced} = ?',
      whereArgs: [1],
    );
  }
}
