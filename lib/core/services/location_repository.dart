import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/location_entity.dart';

/// Repository for location CRUD operations using sqflite.
/// Handles batch inserts, time-range queries, sync status updates,
/// and conversion to LatLng lists for map display.
class LocationRepository {
  final Logger _logger = Logger();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> initialize() async {
    await _dbHelper.database;
    _logger.i('LocationRepository initialized');
  }

  // ------------------------------------------------------------------
  // Insert
  // ------------------------------------------------------------------

  /// Insert a single location.
  Future<int> insert(LocationEntity location) async {
    final db = await _dbHelper.database;
    return db.insert(DatabaseHelper.tableLocations, location.toMap());
  }

  /// Batch insert multiple locations inside a single transaction.
  /// This minimizes I/O overhead compared to individual inserts.
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

  // ------------------------------------------------------------------
  // Query
  // ------------------------------------------------------------------

  /// Get all locations ordered by timestamp (oldest first).
  Future<List<LocationEntity>> getAll({int? limit}) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.tableLocations,
      orderBy: '${DatabaseHelper.colTimestamp} DESC',
      limit: limit,
    );
    return maps.map((m) => LocationEntity.fromMap(m)).toList();
  }

  /// Query locations within a specific time range (inclusive).
  /// Returns ordered by timestamp ascending for route display.
  Future<List<LocationEntity>> getBetween({
    required DateTime start,
    required DateTime end,
  }) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.tableLocations,
      where:
          '${DatabaseHelper.colTimestamp} >= ? AND ${DatabaseHelper.colTimestamp} <= ?',
      whereArgs: [
        start.toUtc().toIso8601String(),
        end.toUtc().toIso8601String(),
      ],
      orderBy: '${DatabaseHelper.colTimestamp} DESC',
    );
    return maps.map((m) => LocationEntity.fromMap(m)).toList();
  }

  /// Get locations that haven't been synced to the server yet.
  Future<List<LocationEntity>> getUnsynced({int? limit}) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.tableLocations,
      where: '${DatabaseHelper.colIsSynced} = ?',
      whereArgs: [0],
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

  // ------------------------------------------------------------------
  // Update
  // ------------------------------------------------------------------

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

  // ------------------------------------------------------------------
  // Delete
  // ------------------------------------------------------------------

  /// Delete all locations (use with caution — mainly for testing).
  Future<int> deleteAll() async {
    final db = await _dbHelper.database;
    return db.delete(DatabaseHelper.tableLocations);
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
