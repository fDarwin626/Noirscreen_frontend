import 'package:crypto/crypto.dart';
import 'dart:convert';

class FileNameParser {
  // Parse video filename and extract metadata
  static Map<String, dynamic> parseFileName(String filePath) {
    // Get filename without path
    final fileName = filePath.split('/').last;
    
    // Remove extension
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.(mp4|mkv|avi|mov|webm|flv|wmv)$', caseSensitive: false), '');
    
    // Detect season and episode pattern (S01E05, 1x05, etc.)
    String? seasonEpisode;
    int? episodeNumber;
    String? seriesId;
    
    // Pattern 1: S01E05 or s01e05
    final pattern1 = RegExp(r'[Ss](\d{1,2})[Ee](\d{1,3})');
    final match1 = pattern1.firstMatch(nameWithoutExt);
    
    if (match1 != null) {
      final season = match1.group(1);
      final episode = match1.group(2);
      seasonEpisode = 'S${season!.padLeft(2, '0')}E${episode!.padLeft(2, '0')}';
      episodeNumber = int.parse(episode);
      
      // Extract series name (everything before season/episode)
      final seriesName = nameWithoutExt.substring(0, match1.start).trim();
      seriesId = _generateSeriesId(seriesName);
    } else {
      // Pattern 2: 1x05 or 1X05
      final pattern2 = RegExp(r'(\d{1,2})[xX](\d{1,3})');
      final match2 = pattern2.firstMatch(nameWithoutExt);
      
      if (match2 != null) {
        final season = match2.group(1);
        final episode = match2.group(2);
        seasonEpisode = 'S${season!.padLeft(2, '0')}E${episode!.padLeft(2, '0')}';
        episodeNumber = int.parse(episode);
        
        final seriesName = nameWithoutExt.substring(0, match2.start).trim();
        seriesId = _generateSeriesId(seriesName);
      }
    }
    
    // Clean title
    String cleanTitle = nameWithoutExt;
    
    // Remove season/episode pattern if found
    if (seasonEpisode != null) {
      cleanTitle = cleanTitle.replaceAll(RegExp(r'[Ss]\d{1,2}[Ee]\d{1,3}'), '');
      cleanTitle = cleanTitle.replaceAll(RegExp(r'\d{1,2}[xX]\d{1,3}'), '');
    }
    
    // Remove common patterns
    cleanTitle = cleanTitle
        .replaceAll(RegExp(r'\d{3,4}p'), '') // Remove 720p, 1080p, etc.
        .replaceAll(RegExp(r'\[(.*?)\]'), '') // Remove [tags]
        .replaceAll(RegExp(r'\((.*?)\)'), '') // Remove (tags)
        .replaceAll(RegExp(r'\{(.*?)\}'), '') // Remove {tags}
        .replaceAll(RegExp(r'BluRay|BRRip|WEBRip|HDRip|DVDRip|HDTV', caseSensitive: false), '')
        .replaceAll(RegExp(r'x264|x265|H264|H265|HEVC', caseSensitive: false), '')
        .replaceAll(RegExp(r'AAC|AC3|DTS|MP3', caseSensitive: false), '')
        .replaceAll(RegExp(r'5\.1|7\.1|2\.0'), '')
        .replaceAll(RegExp(r'-\w+$'), '') // Remove -RARBG, -YTS, etc. at end
        .replaceAll('.', ' ') // Replace dots with spaces
        .replaceAll('_', ' ') // Replace underscores with spaces
        .replaceAll('-', ' ') // Replace dashes with spaces
        .replaceAll(RegExp(r'\s+'), ' ') // Collapse multiple spaces
        .trim();
    
    // Truncate long titles (keep first 40 chars)
    if (cleanTitle.length > 40) {
      cleanTitle = '${cleanTitle.substring(0, 37)}...';
    }
    
    // Truncate garbage filenames (long random strings)
    if (_isGarbageFilename(cleanTitle)) {
      cleanTitle = _truncateGarbageFilename(fileName);
    }
    
    // If title is empty after cleaning, use original filename
    if (cleanTitle.isEmpty) {
      cleanTitle = fileName.substring(0, fileName.length > 40 ? 37 : fileName.length);
      if (fileName.length > 40) cleanTitle += '...';
    }
    
    return {
      'title': cleanTitle,
      'seasonEpisode': seasonEpisode,
      'episodeNumber': episodeNumber,
      'seriesId': seriesId,
    };
  }
  
  // Generate unique series ID from series name
  static String _generateSeriesId(String seriesName) {
    final cleaned = seriesName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    
    return cleaned.isEmpty ? 'unknown-series' : cleaned;
  }
  
  // Check if filename looks like garbage (random strings)
  static bool _isGarbageFilename(String name) {
    // Check for long sequences of numbers/letters without spaces
    final hasLongSequence = RegExp(r'[a-zA-Z0-9]{15,}').hasMatch(name);
    
    // Check for very low ratio of spaces to characters
    final spaceRatio = ' '.allMatches(name).length / (name.length > 0 ? name.length : 1);
    
    return hasLongSequence || spaceRatio < 0.05;
  }
  
  // Truncate garbage filename to readable length
  static String _truncateGarbageFilename(String fileName) {
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.(mp4|mkv|avi|mov|webm|flv|wmv)$', caseSensitive: false), '');
    
    if (nameWithoutExt.length <= 20) {
      return nameWithoutExt;
    }
    
    return '${nameWithoutExt.substring(0, 17)}...';
  }
  
  // Generate unique ID for video file
  static String generateVideoId(String filePath) {
    final bytes = utf8.encode(filePath);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16); // Use first 16 chars of hash
  }
  
  // Determine category based on file path
  static String determineCategory(String filePath) {
    final lowerPath = filePath.toLowerCase();
    
    if (lowerPath.contains('whatsapp')) {
      return 'whatsapp';
    } else if (lowerPath.contains('download')) {
      return 'downloaded';
    } else if (lowerPath.contains('movies')) {
      return 'movies';
    } else if (lowerPath.contains('dcim') || lowerPath.contains('camera')) {
      return 'camera';
    } else if (lowerPath.contains('tv') || lowerPath.contains('shows')) {
      return 'tvshows';
    }
    
    return 'other';
  }
}