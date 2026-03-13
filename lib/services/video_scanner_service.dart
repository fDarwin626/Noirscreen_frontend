import 'dart:io';
import 'package:noirscreen/modals/video_model.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/filename_parser.dart';
import 'video_database_service.dart';

class VideoScannerService {
  final VideoDatabaseService _dbService = VideoDatabaseService();
  
  // Supported video extensions
  static const List<String> _videoExtensions = [
    '.mp4', '.mkv', '.avi', '.mov', '.webm', '.flv', '.wmv', '.m4v', '.3gp'
  ];
  
  // Folders to scan
  static const List<String> _scanFolders = [
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Downloads',
    '/storage/emulated/0/Movies',
    '/storage/emulated/0/WhatsApp/Media/WhatsApp Video',
    '/storage/emulated/0/DCIM',
    '/storage/emulated/0/Videos',
  ];
  
  // Request storage permissions
  Future<bool> requestPermissions() async {
    // Check Android version
    if (Platform.isAndroid) {
      final androidInfo = await _getAndroidVersion();
      
      if (androidInfo >= 13) {
        // Android 13+ (API 33+) - Request READ_MEDIA_VIDEO
        final status = await Permission.videos.request();
        return status.isGranted;
      } else if (androidInfo >= 11) {
        // Android 11-12 (API 30-32) - Request MANAGE_EXTERNAL_STORAGE
        final status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          // Fallback to READ_EXTERNAL_STORAGE
          final readStatus = await Permission.storage.request();
          return readStatus.isGranted;
        }
        return status.isGranted;
      } else {
        // Android 10 and below - Request READ_EXTERNAL_STORAGE
        final status = await Permission.storage.request();
        return status.isGranted;
      }
    }
    
    return false;
  }
  
  // Get Android SDK version
  Future<int> _getAndroidVersion() async {
    // This is a simplified version - you might want to use device_info_plus
    // For now, assume Android 13+ (most users)
    return 33;
  }
  
  // Scan device for videos
  Future<List<VideoModel>> scanVideos({
    Function(int current, int total)? onProgress,
  }) async {
    final List<VideoModel> videos = [];
    int processedFiles = 0;
    int totalFiles = 0;
    
    // First, count total files for progress tracking
    for (final folderPath in _scanFolders) {
      final folder = Directory(folderPath);
      if (await folder.exists()) {
        try {
          await for (final entity in folder.list(recursive: true)) {
            if (entity is File && _isVideoFile(entity.path)) {
              totalFiles++;
            }
          }
        } catch (e) {
          print('Error scanning folder $folderPath: $e');
        }
      }
    }
    
    // Now scan and process files
    for (final folderPath in _scanFolders) {
      final folder = Directory(folderPath);
      if (await folder.exists()) {
        try {
          await for (final entity in folder.list(recursive: true)) {
            if (entity is File && _isVideoFile(entity.path)) {
              final video = await _processVideoFile(entity);
              if (video != null) {
                videos.add(video);
                
                // Save to database immediately
                await _dbService.insertVideo(video);
              }
              
              processedFiles++;
              onProgress?.call(processedFiles, totalFiles);
            }
          }
        } catch (e) {
          print('Error scanning folder $folderPath: $e');
        }
      }
    }
    
    return videos;
  }
  
  // Check if file is a video
  bool _isVideoFile(String path) {
    final extension = path.toLowerCase().substring(path.lastIndexOf('.'));
    return _videoExtensions.contains(extension);
  }
  
  // Process individual video file
  Future<VideoModel?> _processVideoFile(File file) async {
    try {
      final filePath = file.path;
      final fileSize = await file.length();
      final dateAdded = await file.lastModified();
      
      // Parse filename
      final parsed = FileNameParser.parseFileName(filePath);
      
      // Generate unique ID
      final videoId = FileNameParser.generateVideoId(filePath);
      
      // Determine category
      final category = FileNameParser.determineCategory(filePath);
      
      // Create video model
      return VideoModel(
        id: videoId,
        title: parsed['title'] as String,
        filePath: filePath,
        fileSize: fileSize,
        dateAdded: dateAdded,
        category: category,
        seasonEpisode: parsed['seasonEpisode'] as String?,
        episodeNumber: parsed['episodeNumber'] as int?,
        seriesId: parsed['seriesId'] as String?,
      );
    } catch (e) {
      print('Error processing video file ${file.path}: $e');
      return null;
    }
  }
  
  // Quick scan (only check for new files)
  Future<List<VideoModel>> quickScan() async {
    final existingVideos = await _dbService.getAllVideos();
    final existingPaths = existingVideos.map((v) => v.filePath).toSet();
    
    final List<VideoModel> newVideos = [];
    
    for (final folderPath in _scanFolders) {
      final folder = Directory(folderPath);
      if (await folder.exists()) {
        try {
          await for (final entity in folder.list(recursive: true)) {
            if (entity is File && 
                _isVideoFile(entity.path) && 
                !existingPaths.contains(entity.path)) {
              final video = await _processVideoFile(entity);
              if (video != null) {
                newVideos.add(video);
                await _dbService.insertVideo(video);
              }
            }
          }
        } catch (e) {
          print('Error in quick scan for $folderPath: $e');
        }
      }
    }
    
    return newVideos;
  }
}