import 'package:noirscreen/models/video_model.dart';

import 'video_scanner_service.dart';
import 'video_database_service.dart';
import 'thumbnail_generator_service.dart';

class VideoManagerService {
  final VideoScannerService _scanner = VideoScannerService();
  final VideoDatabaseService _database = VideoDatabaseService();
  final ThumbnailGeneratorService _thumbnailGenerator = ThumbnailGeneratorService();

  // Full scan: scan videos + generate thumbnails
  Future<List<VideoModel>> fullScan({
    Function(String status, int current, int total)? onProgress,
  }) async {
    try {
      print('🚀 MANAGER: Starting full scan...');
      // Step 1: Request permissions
      onProgress?.call('Requesting permissions...', 0, 100);
      final hasPermission = await _scanner.requestPermissions();
      
      if (!hasPermission) {
        throw Exception('Storage permission denied');
      }

      // Step 2: Scan for videos
      onProgress?.call('Scanning for videos...', 10, 100);
      
      final videos = await _scanner.scanVideos(
        onProgress: (current, total) {
          final progress = 10 + ((current / total) * 40).toInt();
          onProgress?.call('Scanning... ($current/$total)', progress, 100);
        },
      );
print('📹 MANAGER: Scanner found ${videos.length} videos');
      if (videos.isEmpty) {
        onProgress?.call('No videos found', 100, 100);
        return [];
      }

      // Step 3: Generate thumbnails
      onProgress?.call('Generating thumbnails...', 50, 100);
      
      int thumbnailsGenerated = 0;
      for (int i = 0; i < videos.length; i++) {
        final video = videos[i];
        
        // Generate thumbnail
        final thumbnailPath = await _thumbnailGenerator.generateThumbnail(video);
        
        if (thumbnailPath != null) {
          // Update video with thumbnail path
          final updatedVideo = video.copyWith(thumbnailPath: thumbnailPath);
          videos[i] = updatedVideo;
          
          // Update in database
          await _database.updateVideo(updatedVideo);
          
          thumbnailsGenerated++;
        }
        
        // Report progress
        final progress = 50 + ((i / videos.length) * 45).toInt();
        onProgress?.call(
          'Generating thumbnails... ($thumbnailsGenerated/${videos.length})',
          progress,
          100,
        );
      }

      onProgress?.call('Scan complete!', 100, 100);
      print('✅ MANAGER: Full scan complete! ${videos.length} videos processed, $thumbnailsGenerated thumbnails generated');
      return videos;
    } catch (e) {
      print('Full scan error: $e');
      print('✅ MANAGER: Full scan failed!');
      onProgress?.call('Error: ${e.toString()}', 0, 100);
      rethrow;
    }
  }

  // Quick scan: only find new videos
  Future<List<VideoModel>> quickScan({
    Function(String status)? onProgress,
  }) async {
    try {
      onProgress?.call('Checking for new videos...');
      
      final newVideos = await _scanner.quickScan();
      
      if (newVideos.isEmpty) {
        onProgress?.call('No new videos found');
        return [];
      }

      onProgress?.call('Generating thumbnails for ${newVideos.length} new videos...');
      
      // Generate thumbnails for new videos
      for (int i = 0; i < newVideos.length; i++) {
        final video = newVideos[i];
        final thumbnailPath = await _thumbnailGenerator.generateThumbnail(video);
        
        if (thumbnailPath != null) {
          final updated = video.copyWith(thumbnailPath: thumbnailPath);
          newVideos[i] = updated;
          await _database.updateVideo(updated);
        }
      }

      onProgress?.call('Found ${newVideos.length} new videos');
      return newVideos;
    } catch (e) {
      print('Quick scan error: $e');
      onProgress?.call('Error: ${e.toString()}');
      return [];
    }
  }

// Get all videos from database
Future<List<VideoModel>> getAllVideos() async {
  print('🔍 MANAGER: getAllVideos() called');
  final videos = await _database.getAllVideos();
  print('📊 MANAGER: Returning ${videos.length} videos');
  return videos;
}
// Get videos by category
Future<List<VideoModel>> getVideosByCategory(String category) async {
  print('🔍 MANAGER: getVideosByCategory("$category") called');
  final videos = await _database.getVideosByCategory(category);
  print('📊 MANAGER: Returning ${videos.length} videos for category "$category"');
  return videos;
}

  // Get most streamed videos
  Future<List<VideoModel>> getMostStreamed() async {
    return await _database.getMostStreamed();
  }

  // Get recently watched
  Future<List<VideoModel>> getRecentlyWatched() async {
    return await _database.getRecentlyWatched();
  }

  // Update video (e.g., after watching)
  Future<void> updateVideo(VideoModel video) async {
    await _database.updateVideo(video);
  }

  // Get cache size
  Future<int> getCacheSize() async {
    return await _thumbnailGenerator.getCacheSize();
  }

  // Clear thumbnail cache
  Future<void> clearCache() async {
    await _thumbnailGenerator.clearCache();
  }

  // Clear all data (videos + cache)
  Future<void> clearAllData() async {
    await _database.clearAll();
    await _thumbnailGenerator.clearCache();
  }
}