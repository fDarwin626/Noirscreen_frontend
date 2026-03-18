import 'package:noirscreen/models/series_model.dart';
import 'package:noirscreen/models/video_model.dart';
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
    print(
      '💾 DATABASE: Inserting video - ID: ${video.id}, Title: ${video.title}',
    );
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
    print('💾 DATABASE: Retrieved all videos - Count: ${maps.length}');
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
    print('💾 DATABASE: Retrieved videos by category - Count: ${maps.length}');
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

  // Get all TV Series grouped (2+ episodes only)
  Future<List<SeriesModel>> getSeriesGroups() async {
    final db = await database;
    final seriesIdMaps = await db.rawQuery('''
      SELECT 
        series_id,
        COUNT(*) as episode_count,
        SUM(CASE WHEN is_completed = 1 THEN 1 ELSE 0 END) as watched_count,
        MAX(last_watched) as last_watched
      FROM $_tableName
      WHERE series_id IS NOT NULL AND series_id != ''
      GROUP BY series_id
      HAVING COUNT(*) >= 2
      ORDER BY MAX(last_watched) DESC NULLS LAST
    ''');
    print('💾 DATABASE: Found ${seriesIdMaps.length} series groups');

    final List<SeriesModel> seriesList = [];

    for (final row in seriesIdMaps) {
      final seriesId = row['series_id'] as String;
      final totalEpisodes = (row['episode_count'] as int?) ?? 0;
      final watchedEpisodes = (row['watched_count'] as int?) ?? 0;
      final lastWatchedStr = row['last_watched'] as String?;

      final currentEpisode = await getCurrentEpisode(seriesId);
      final headerEpisode =
          currentEpisode ?? await getNextUnwatchedEpisode(seriesId);

      final firstEpisodeMaps = await db.query(
        _tableName,
        where: 'series_id = ?',
        whereArgs: [seriesId],
        orderBy: 'episode_number ASC',
        limit: 1,
      );

      if (firstEpisodeMaps.isEmpty) continue;

      final firstEpisode = VideoModel.fromJson(firstEpisodeMaps.first);
      final seriesTitle = seriesId
          .split('-')
          .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
          .join(' ');

      final posterPath =
          headerEpisode?.thumbnailPath ?? firstEpisode.thumbnailPath;

      DateTime lastWatched;
      try {
        lastWatched = lastWatchedStr != null
            ? DateTime.parse(lastWatchedStr)
            : firstEpisode.dateAdded;
      } catch (_) {
        lastWatched = firstEpisode.dateAdded;
      }

      seriesList.add(
        SeriesModel(
          id: seriesId,
          title: seriesTitle,
          posterUrl: posterPath,
          totalEpisodes: totalEpisodes,
          watchedEpisodes: watchedEpisodes,
          currentEpisode: headerEpisode,
          lastWatched: lastWatched,
        ),
      );
    }

    return seriesList;
  }

  // Clear all videos
  Future<void> clearAll() async {
    final db = await database;
    await db.delete(_tableName);
  }
}
