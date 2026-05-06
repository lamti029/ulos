import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('ulos.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getApplicationDocumentsDirectory();
    const dbName = 'ulos.db';
    final path = join(dbPath.path, dbName);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE locations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      lat REAL NOT NULL,
      lng REAL NOT NULL,
      timestamp TEXT NOT NULL,
      accuracy REAL,
      altitude REAL,
      speed REAL,
      is_mocked INTEGER DEFAULT 0,
      survei_id INTEGER,
      is_synced INTEGER DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now'))
    )
    ''');
  }

  static const String tableLocations = 'locations';
  static const String colId = 'id';
  static const String colLat = 'lat';
  static const String colLng = 'lng';
  static const String colTimestamp = 'timestamp';
  static const String colAccuracy = 'accuracy';
  static const String colAltitude = 'altitude';
  static const String colSpeed = 'speed';
  static const String colIsMocked = 'is_mocked';
  static const String colSurveiId = 'survei_id';
  static const String colIsSynced = 'is_synced';
  static const String colCreatedAt = 'created_at';
}
