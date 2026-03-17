import 'dart:io';
import 'package:noirscreen/models/video_model.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/filename_parser.dart';
import 'video_database_service.dart';

class VideoScannerService {
  final VideoDatabaseService _dbService = VideoDatabaseService();
  
  // Supported video extensions
  static const List<String> _videoExtensions = [
    '.mp4', '.mkv', '.avi', '.mov', '.webm', '.flv', '.wmv', '.m4v', '.3gp'
  ];
  
static const List<String> _scanFolders = [
  // Real device paths
  '/storage/emulated/0/Download',
  '/storage/emulated/0/Downloads',
  '/storage/emulated/0/Movies',
  '/storage/emulated/0/DCIM',
  '/storage/emulated/0/DCIM/Camera',
  '/storage/emulated/0/Pictures',
  '/storage/emulated/0/Videos',
  '/storage/emulated/0/WhatsApp/Media/WhatsApp Video',
  
  // Emulator-specific paths (sdk_gphone)
  '/sdk_gphone64_x86_64/Download',
  '/sdk_gphone64_x86_64/Downloads',
  '/sdk_gphone64_x86_64/Movies',
  '/sdk_gphone64_x86_64/DCIM',
  '/sdk_gphone64_x86_64/Pictures',
  '/sdk_gphone64_x86_64/Videos',
  
  // Alternative paths
  '/sdcard/Download',
  '/sdcard/Downloads',
  '/sdcard/Movies',
  '/sdcard/DCIM',
  '/sdcard/Pictures',
  '/sdcard/Videos',
];
  
  // Request storage permissions
  Future<bool> requestPermissions() async {
    print('🔐 SCANNER: Requesting storage permissions...');
    
    if (Platform.isAndroid) {
      // Try multiple permission strategies
      
      // Strategy 1: Request READ_MEDIA_VIDEO (Android 13+)
      var status = await Permission.videos.request();
      print('📱 SCANNER: Permission.videos status: ${status.isGranted}');
      
      if (status.isGranted) {
        print('✅ SCANNER: Permission.videos GRANTED');
        return true;
      }
      
      // Strategy 2: Request MANAGE_EXTERNAL_STORAGE
      status = await Permission.manageExternalStorage.request();
      print('📱 SCANNER: Permission.manageExternalStorage status: ${status.isGranted}');
      
      if (status.isGranted) {
        print('✅ SCANNER: Permission.manageExternalStorage GRANTED');
        return true;
      }
      
      // Strategy 3: Request READ_EXTERNAL_STORAGE (fallback)
      status = await Permission.storage.request();
      print('📱 SCANNER: Permission.storage status: ${status.isGranted}');
      
      if (status.isGranted) {
        print('✅ SCANNER: Permission.storage GRANTED');
        return true;
      }
      
      print('❌ SCANNER: ALL PERMISSIONS DENIED!');
      return false;
    }
    
    return false;
  }
  
  // Scan device for videos
  Future<List<VideoModel>> scanVideos({
    Function(int current, int total)? onProgress,
  }) async {
    print('🔍 SCANNER: Starting scan in ${_scanFolders.length} folders');
    
    final List<VideoModel> videos = [];
    int processedFiles = 0;
    int totalFiles = 0;
    
    // Debug: Check which folders actually exist
    for (final folderPath in _scanFolders) {
      final folder = Directory(folderPath);
      final exists = await folder.exists();
      print('📁 SCANNER: Checking $folderPath - Exists: $exists');
      
      if (exists) {
        try {
          final contents = await folder.list().toList();
          print('   📂 Contains ${contents.length} items');
        } catch (e) {
          print('   ❌ Error reading folder: $e');
        }
      }
    }
    
    // First, count total files for progress tracking
    for (final folderPath in _scanFolders) {
      final folder = Directory(folderPath);
      if (await folder.exists()) {
        try {
          await for (final entity in folder.list(recursive: true)) {
            if (entity is File && _isVideoFile(entity.path)) {
              totalFiles++;
              print('🎥 SCANNER: Found video file: ${entity.path}');
            }
          }
        } catch (e) {
          print('❌ SCANNER: Error scanning folder $folderPath: $e');
        }
      }
    }
    
    print('📊 SCANNER: Found $totalFiles video files total');
    
    if (totalFiles == 0) {
      print('⚠️ SCANNER: No video files found in any folder!');
      return [];
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
                print('💾 SCANNER: Saved video to DB: ${video.title}');
              }
              
              processedFiles++;
              onProgress?.call(processedFiles, totalFiles);
            }
          }
        } catch (e) {
          print('❌ SCANNER: Error scanning folder $folderPath: $e');
        }
      }
    }
    
    print('✅ SCANNER: Scan complete! Found ${videos.length} videos');
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
      final video = VideoModel(
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
      
      return video;
    } catch (e) {
      print('❌ SCANNER: Error processing video file ${file.path}: $e');
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
          print('❌ SCANNER: Error in quick scan for $folderPath: $e');
        }
      }
    }
    
    return newVideos;
  }
}