import 'package:noirscreen/modals/video_model.dart';

class SeriesModel {
  final String id; // e.g., "one-piece"
  final String title; // e.g., "One Piece"
  final String? posterUrl; // Series poster (from first episode or API)
  final int totalEpisodes; // Total episodes found
  final int watchedEpisodes; // Episodes marked complete
  final VideoModel? currentEpisode; // Currently watching episode
  final DateTime lastWatched; // Last time any episode was watched

  SeriesModel({
    required this.id,
    required this.title,
    this.posterUrl,
    required this.totalEpisodes,
    this.watchedEpisodes = 0,
    this.currentEpisode,
    required this.lastWatched,
  });

  // Calculate watch progress percentage
  double get progressPercentage {
    if (totalEpisodes == 0) return 0.0;
    return (watchedEpisodes / totalEpisodes) * 100;
  }

  // Check if series is completed
  bool get isCompleted => watchedEpisodes == totalEpisodes;
}