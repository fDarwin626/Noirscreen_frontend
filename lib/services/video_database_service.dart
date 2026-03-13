import 'package:noirscreen/modals/video_model.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class VideoDatabaseService {
  static Database? _database;
  static const String _tableName = 'videos';

  // Get database instance (singleton pattern)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Initialize database
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'noirscreen_videos.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
        CREATE TABLE $_tableName (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          file_path TEXT NOT NULL UNIQUE,
          thumbnail_path TEXT,
          poster_url TEXT,
          file_size INTEGER NOT NULL,
          date_added TEXT NOT NULL,
          duration INTEGER DEFAULT 0,
          category TEXT NOT NULL,
          season_episode TEXT,
          series_id TEXT,
          episode_number INTEGER,
          watch_progress INTEGER DEFAULT 0,
          is_completed INTEGER DEFAULT 0,
          watch_count INTEGER DEFAULT 0,
          stream_count INTEGER DEFAULT 0,
          last_watched TEXT
        )
      ''');
        // Create indexes for faster queries
        await db.execute('CREATE INDEX idx_category ON $_tableName(category)');
        await db.execute(
          'CREATE INDEX idx_stream_count ON $_tableName(stream_count DESC)',
        );
        await db.execute(
          'CREATE INDEX idx_last_watched ON $_tableName(last_watched DESC)',
        );
        await db.execute(
          'CREATE INDEX idx_series_id ON $_tableName(series_id)',
        );
        await db.execute(
          'CREATE INDEX idx_episode_number ON $_tableName(episode_number)',
        );
      },
    );
  }

  // Insert video
  Future<void> insertVideo(VideoModel video) async {
    final db = await database;
    await db.insert(
      _tableName,
      video.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Get all videos
  Future<List<VideoModel>> getAllVideos() async {
    final db = await database;
    final maps = await db.query(_tableName);
    return maps.map((map) => VideoModel.fromJson(map)).toList();
  }

  // Get videos by category
  Future<List<VideoModel>> getVideosByCategory(String category) async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      where: 'category = ?',
      whereArgs: [category],
    );
    return maps.map((map) => VideoModel.fromJson(map)).toList();
  }

  // Get all episode of Tv series
  Future<List<VideoModel>> getEpisodeBySeries(String seriesId) async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      where: 'series_id = ?',
      whereArgs: [seriesId],
      orderBy: 'episode_number ASC',
    );
    return maps.map((map) => VideoModel.fromJson(map)).toList();
  }


// Get current watching episode for a series
Future<VideoModel?> getCurrentEpisode(String seriesId) async {
  final db = await database;
  final maps = await db.query(
    _tableName,
    where: 'series_id = ? AND is_completed = 0 AND watch_progress > 0',
    whereArgs: [seriesId],
    orderBy: 'episode_number ASC',
    limit: 1,
  );
  if (maps.isEmpty) return null;
  return VideoModel.fromJson(maps.first);
}

// Get next unwatched episode
Future<VideoModel?> getNextUnwatchedEpisode(String seriesId) async {
  final db = await database;
  final maps = await db.query(
    _tableName,
    where: 'series_id = ? AND is_completed = 0',
    whereArgs: [seriesId],
    orderBy: 'episode_number ASC',
    limit: 1,
  );
  if (maps.isEmpty) return null;
  return VideoModel.fromJson(maps.first);
}

  // Get most streamed videos (stream_count >= 2)
  Future<List<VideoModel>> getMostStreamed() async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      where: 'stream_count >= ?',
      whereArgs: [2],
      orderBy: 'stream_count DESC',
      limit: 20,
    );
    return maps.map((map) => VideoModel.fromJson(map)).toList();
  }

  // Get recently watched videos
  Future<List<VideoModel>> getRecentlyWatched() async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      where: 'last_watched IS NOT NULL',
      orderBy: 'last_watched DESC',
      limit: 10,
    );
    return maps.map((map) => VideoModel.fromJson(map)).toList();
  }

  // Update video
  Future<void> updateVideo(VideoModel video) async {
    final db = await database;
    await db.update(
      _tableName,
      video.toJson(),
      where: 'id = ?',
      whereArgs: [video.id],
    );
  }

  // Delete video
  Future<void> deleteVideo(String id) async {
    final db = await database;
    await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  }

  // Clear all videos
  Future<void> clearAll() async {
    final db = await database;
    await db.delete(_tableName);
  }
}
