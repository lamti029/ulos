import 'package:logger/logger.dart';

import '../models/location_entity.dart';

class BackgroundLocationBuffer {
  final Logger _logger;

  final List<LocationEntity> _buffer = [];
  DateTime? _lastFlushAt;

  final int flushMinBufferSize;
  final int flushMaxAgeSeconds;

  BackgroundLocationBuffer({
    required Logger logger,
    this.flushMinBufferSize = 15,
    this.flushMaxAgeSeconds = 60,
  }) : _logger = logger;

  List<LocationEntity> get snapshot => List.unmodifiable(_buffer);
  int get length => _buffer.length;

  bool get isEmpty => _buffer.isEmpty;

  void add(LocationEntity entity) {
    _buffer.add(entity);
    _logger.d('Buffered (${_buffer.length})');
  }

  bool shouldFlush() {
    if (_buffer.isEmpty) return false;

    final now = DateTime.now();
    final ageSeconds = _lastFlushAt == null
        ? flushMaxAgeSeconds + 1
        : now.difference(_lastFlushAt!).inSeconds;

    if (_buffer.length < flushMinBufferSize &&
        ageSeconds < flushMaxAgeSeconds) {
      return false;
    }
    return true;
  }

  DateTime get lastFlushAt =>
      _lastFlushAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  List<LocationEntity> drain() {
    final batch = List<LocationEntity>.from(_buffer);
    _buffer.clear();
    _lastFlushAt = DateTime.now();
    return batch;
  }

  void rollback(List<LocationEntity> batch) {
    if (batch.isEmpty) return;
    _buffer.insertAll(0, batch);
  }

  void clear() {
    _buffer.clear();
    _lastFlushAt = null;
  }
}
