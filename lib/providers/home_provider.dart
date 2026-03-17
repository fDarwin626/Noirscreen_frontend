import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/video_model.dart';
import '../services/video_manager_service.dart';

// Video manager service provider
final videoManagerProvider = Provider((ref) => VideoManagerService());

// All videos provider
final allVideosProvider = FutureProvider<List<VideoModel>>((ref) async {
  print('🔄 PROVIDER: allVideosProvider called');
  final manager = ref.watch(videoManagerProvider);
  final videos = await manager.getAllVideos();
  print('✅ PROVIDER: allVideosProvider returned ${videos.length} videos');
  return videos;
});

// Downloaded videos provider
final downloadedVideosProvider = FutureProvider<List<VideoModel>>((ref) async {
  print('🔄 PROVIDER: downloadedVideosProvider called');
  final manager = ref.watch(videoManagerProvider);
  final videos = await manager.getVideosByCategory('downloaded');
  print('✅ PROVIDER: downloadedVideosProvider returned ${videos.length} videos');
  return videos;
});

// WhatsApp videos provider
final whatsappVideosProvider = FutureProvider<List<VideoModel>>((ref) async {
  print('🔄 PROVIDER: whatsappVideosProvider called');
  final manager = ref.watch(videoManagerProvider);
  final videos = await manager.getVideosByCategory('whatsapp');
  print('✅ PROVIDER: whatsappVideosProvider returned ${videos.length} videos');
  return videos;
});

// Most streamed videos provider
final mostStreamedProvider = FutureProvider<List<VideoModel>>((ref) async {
  print('🔄 PROVIDER: mostStreamedProvider called');
  final manager = ref.watch(videoManagerProvider);
  final videos = await manager.getMostStreamed();
  print('✅ PROVIDER: mostStreamedProvider returned ${videos.length} videos');
  return videos;
});

// Recently watched provider
final recentlyWatchedProvider = FutureProvider<List<VideoModel>>((ref) async {
  print('🔄 PROVIDER: recentlyWatchedProvider called');
  final manager = ref.watch(videoManagerProvider);
  final videos = await manager.getRecentlyWatched();
  print('✅ PROVIDER: recentlyWatchedProvider returned ${videos.length} videos');
  return videos;
});

// Movies provider
final moviesProvider = FutureProvider<List<VideoModel>>((ref) async {
  print('🔄 PROVIDER: moviesProvider called');
  final manager = ref.watch(videoManagerProvider);
  final videos = await manager.getVideosByCategory('movies');
  print('✅ PROVIDER: moviesProvider returned ${videos.length} videos');
  return videos;
});

// Camera videos provider
final cameraVideosProvider = FutureProvider<List<VideoModel>>((ref) async {
  print('🔄 PROVIDER: cameraVideosProvider called');
  final manager = ref.watch(videoManagerProvider);
  final videos = await manager.getVideosByCategory('camera');
  print('✅ PROVIDER: cameraVideosProvider returned ${videos.length} videos');
  return videos;
});