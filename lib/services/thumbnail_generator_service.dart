import 'dart:io';
import 'package:noirscreen/models/video_model.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_services.dart';

class ThumbnailGeneratorService {
  // Get thumbnail cache directory
  Future<Directory> _getThumbnailCacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final thumbDir = Directory('${appDir.path}/thumbnails');

    if (!await thumbDir.exists()) {
      await thumbDir.create(recursive: true);
    }

    return thumbDir;
  }

  // SECURITY: Validate video file before processing
  Future<bool> _validateVideoFile(String filePath) async {
    try {
      final file = File(filePath);

      // Check existence
      if (!await file.exists()) return false;

      // Check size (max 5GB)
      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024 * 1024) return false;

      // Check extension whitelist
      final ext = filePath.toLowerCase().split('.').last;
      const allowed = ['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv', 'm4v', '3gp'];
      if (!allowed.contains(ext)) return false;

      // Check path (prevent traversal)
      const allowedPaths = [
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Downloads',
        '/storage/emulated/0/Movies',
        '/storage/emulated/0/WhatsApp',
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Videos',
      ];

      if (!allowedPaths.any((p) => filePath.startsWith(p))) return false;

      return true;
    } catch (e) {
      return false;
    }
  }

  // Generate thumbnail (Hybrid: API poster OR video frame)
  Future<String?> generateThumbnail(
    VideoModel video, {
    int? timeMs,
  }) async {
    try {
      // Validate video file
      if (!await _validateVideoFile(video.filePath)) {
        print('Video validation failed: ${video.filePath}');
        return null;
      }

      // Step 1: Try backend API for poster
      final posterUrl = await _fetchPosterFromBackend(video.title);

      if (posterUrl != null) {
        final cached = await _downloadAndCachePoster(posterUrl, video.id);
        if (cached != null) return cached;
      }

      // Step 2: Fallback - extract video frame
      return await _extractVideoFrame(video.filePath, video.id, timeMs: timeMs);
    } catch (e) {
      print('Thumbnail error: $e');
      return null;
    }
  }

  // Fetch poster from backend (SECURE - no API key in app)
  Future<String?> _fetchPosterFromBackend(String title) async {
    try {
      // Skip garbage titles
      if (title.contains('...') || title.length < 3) return null;

      // Clean title
      final clean = title
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      if (clean.isEmpty) return null;

      // Call backend API
      final encoded = Uri.encodeComponent(clean);
      final url = Uri.parse('${ApiService.baseUrl}/api/videos/poster?title=$encoded');

      final response = await http.get(url).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('Timeout'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['posterUrl'] != null) {
          return data['posterUrl'] as String;
        }
      }

      return null;
    } catch (e) {
      print('Poster fetch error: $e');
      return null;
    }
  }

  // Download and cache poster
  Future<String?> _downloadAndCachePoster(String url, String videoId) async {
    try {
      // HTTPS only
      if (!url.startsWith('https://')) return null;

      // Domain whitelist
      const trusted = ['media-amazon.com', 'tmdb.org'];
      final uri = Uri.parse(url);
      if (!trusted.any((d) => uri.host.contains(d))) return null;

      // Download
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Timeout'),
      );

      if (response.statusCode != 200) return null;

      // Size check (max 5MB)
      if (response.bodyBytes.length > 5 * 1024 * 1024) return null;

      // Validate image magic bytes
      if (!_isValidImage(response.bodyBytes)) return null;

      // Save to cache
      final cacheDir = await _getThumbnailCacheDir();
      final file = File('${cacheDir.path}/${videoId}_poster.jpg');
      await file.writeAsBytes(response.bodyBytes);

      return file.path;
    } catch (e) {
      print('Cache error: $e');
      return null;
    }
  }

  // Validate image magic bytes
  bool _isValidImage(List<int> bytes) {
    if (bytes.length < 4) return false;
    final h = bytes.sublist(0, 4);

    // JPEG: FF D8 FF
    if (h[0] == 0xFF && h[1] == 0xD8 && h[2] == 0xFF) return true;

    // PNG: 89 50 4E 47
    if (h[0] == 0x89 && h[1] == 0x50 && h[2] == 0x4E && h[3] == 0x47) return true;

    // WebP: 52 49 46 46
    if (h[0] == 0x52 && h[1] == 0x49 && h[2] == 0x46 && h[3] == 0x46) return true;

    return false;
  }

  // Extract frame from video
  Future<String?> _extractVideoFrame(
    String videoPath,
    String videoId, {
    int? timeMs,
  }) async {
    try {
      final cacheDir = await _getThumbnailCacheDir();
      final outputPath = '${cacheDir.path}/${videoId}_thumb.jpg';

      // Check cache
      if (await File(outputPath).exists()) return outputPath;

      // Extract thumbnail
      final thumb = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: cacheDir.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 400,
        quality: 75,
        timeMs: timeMs ?? 10000,
      );

      if (thumb != null) {
        final generated = File(thumb);
        if (await generated.exists()) {
          await generated.rename(outputPath);
          return outputPath;
        }
      }

      return null;
    } catch (e) {
      print('Frame extraction error: $e');
      return null;
    }
  }

  // Generate resume thumbnail (at watch progress timestamp)
  Future<String?> generateResumeThumbnail(VideoModel video) async {
    if (video.watchProgress == 0) return null;
    
    final timeMs = video.watchProgress! * 1000;
    return await _extractVideoFrame(
      video.filePath,
      '${video.id}_resume',
      timeMs: timeMs,
    );
  }

  // Clear cache
  Future<void> clearCache() async {
    try {
      final cacheDir = await _getThumbnailCacheDir();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        await cacheDir.create();
      }
    } catch (e) {
      print('Clear cache error: $e');
    }
  }

  // Get cache size
  Future<int> getCacheSize() async {
    try {
      final cacheDir = await _getThumbnailCacheDir();
      if (!await cacheDir.exists()) return 0;

      int total = 0;
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (e) {
      return 0;
    }
  }
}