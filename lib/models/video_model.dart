// ignore_for_file: public_member_api_docs, sort_constructors_first

class VideoModel {
  final String id;
  final String title;
  final String filePath;
  final String? thumbnailPath;
  final String? posterUrl;
  final int fileSize;
  final DateTime dateAdded;
  final int duration;
  final String category;
  final String? seasonEpisode;
  final int watchCount;
  final int streamCount;
  final DateTime? lastWatched;
  final String? seriesId;
  final int? episodeNumber;
  final int? watchProgress; // in seconds
  final bool isCompleted;

VideoModel({
  required this.id,
  required this.title,
  required this.filePath,
  this.thumbnailPath,
  this.posterUrl,
  required this.fileSize,
  required this.dateAdded,
  this.duration = 0,
  required this.category,
  this.seasonEpisode,
  this.seriesId, 
  this.episodeNumber, 
  this.watchProgress = 0, 
  this.isCompleted = false, 
  this.watchCount = 0,
  this.streamCount = 0,
  this.lastWatched,
});

Map<String, dynamic> toJson() {
  return {
    'id': id,
    'title': title,
    'file_path': filePath,
    'thumbnail_path': thumbnailPath,
    'poster_url': posterUrl,
    'file_size': fileSize,
    'date_added': dateAdded.toIso8601String(),
    'duration': duration,
    'category': category,
    'season_episode': seasonEpisode,
    'series_id': seriesId, 
    'episode_number': episodeNumber, 
    'watch_progress': watchProgress, 
    'is_completed': isCompleted ? 1 : 0, 
    'watch_count': watchCount,
    'stream_count': streamCount,
    'last_watched': lastWatched?.toIso8601String(),
  };
}

factory VideoModel.fromJson(Map<String, dynamic> json) {
  return VideoModel(
    id: json['id'] as String,
    title: json['title'] as String,
    filePath: json['file_path'] as String,
    thumbnailPath: json['thumbnail_path'] as String?,
    posterUrl: json['poster_url'] as String?,
    fileSize: json['file_size'] as int,
    dateAdded: DateTime.parse(json['date_added'] as String),
    duration: json['duration'] as int? ?? 0,
    category: json['category'] as String,
    seasonEpisode: json['season_episode'] as String?,
    seriesId: json['series_id'] as String?, 
    episodeNumber: json['episode_number'] as int?, 
    watchProgress: json['watch_progress'] as int? ?? 0, 
    isCompleted: (json['is_completed'] as int? ?? 0) == 1, 
    watchCount: json['watch_count'] as int? ?? 0,
    streamCount: json['stream_count'] as int? ?? 0,
    lastWatched: json['last_watched'] != null
        ? DateTime.parse(json['last_watched'] as String)
        : null,
  );
}

  VideoModel copyWith({
    String? id,
    String? title,
    String? filePath,
    String? thumbnailPath,
    String? posterUrl,
    int? fileSize,
    DateTime? dateAdded,
    int? duration,
    String? category,
    String? seasonEpisode,
    int? watchCount,
    int? streamCount,
    DateTime? lastWatched,
    String? seriesId,
    int? episodeNumber,
    int? watchProgress,
    bool? isCompleted,
  }) {
    return VideoModel(
      id: id ?? this.id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      posterUrl: posterUrl ?? this.posterUrl,
      fileSize: fileSize ?? this.fileSize,
      dateAdded: dateAdded ?? this.dateAdded,
      duration: duration ?? this.duration,
      category: category ?? this.category,
      seasonEpisode: seasonEpisode ?? this.seasonEpisode,
      watchCount: watchCount ?? this.watchCount,
      streamCount: streamCount ?? this.streamCount,
      lastWatched: lastWatched ?? this.lastWatched,
      seriesId: seriesId ?? this.seriesId,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      watchProgress: watchProgress ?? this.watchProgress,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
