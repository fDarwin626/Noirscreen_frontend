import 'dart:io';
import 'package:noirscreen/models/video_model.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/filename_parser.dart';
import 'video_database_service.dart';

class VideoScannerService {
  final VideoDatabaseService _dbService = VideoDatabaseService();

  static const List<String> _videoExtensions = [
    '.mp4', '.mkv', '.avi', '.mov', '.webm', '.flv', '.wmv', '.m4v', '.3gp'
  ];

  // On Android, /sdcard and /storage/emulated/0 are the SAME directory
  // (symlinks). Scanning both created duplicate entries in the DB.
  // Also removed DCIM root when DCIM/Camera is already listed — same issue.
  // Rule: never list a parent AND its child — pick the most specific one.
  // BUG 6 FIX: kept paths broad enough to cover Xiaomi MIUI and SD cards.
  static const List<String> _scanFolders = [
    // Primary storage — real device
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Downloads',
    '/storage/emulated/0/Movies',
    '/storage/emulated/0/DCIM/Camera',   // ← specific subfolder, not DCIM root
    '/storage/emulated/0/Pictures',
    '/storage/emulated/0/Videos',
    '/storage/emulated/0/WhatsApp/Media/WhatsApp Video',
        // Xiaomi/MIUI specific
    '/storage/emulated/0/MIUI/Gallery',
    '/storage/emulated/0/Telegram',
    '/storage/emulated/0/Telegram/Telegram Video',


    // Emulator paths
    '/sdk_gphone64_x86_64/Download',
    '/sdk_gphone64_x86_64/Downloads',
    '/sdk_gphone64_x86_64/Movies',
    '/sdk_gphone64_x86_64/DCIM/Camera',
    '/sdk_gphone64_x86_64/Pictures',
    '/sdk_gphone64_x86_64/Videos',

    // NOTE: /sdcard/ paths intentionally removed — /sdcard is a symlink to
    // /storage/emulated/0 on all modern Android devices. Scanning both
    // produces duplicates because the resolved real path is identical.
  ];

  Future<bool> requestPermissions() async {
    print('🔐 SCANNER: Requesting storage permissions...');

    if (Platform.isAndroid) {
      var status = await Permission.videos.request();
      if (status.isGranted) return true;

      status = await Permission.manageExternalStorage.request();
      if (status.isGranted) return true;

      status = await Permission.storage.request();
      if (status.isGranted) return true;

      print('❌ SCANNER: ALL PERMISSIONS DENIED!');
      return false;
    }

    return false;
  }

  Future<List<VideoModel>> scanVideos({
    Function(int current, int total)? onProgress,
  }) async {
    print('🔍 SCANNER: Starting scan in ${_scanFolders.length} folders');

    // BUG 5 FIX: deduplicate by resolved real path.
    // On some devices two folder paths resolve to the same inode.
    // We track real paths so the same file is never inserted twice.
    final Set<String> seenRealPaths = {};
    final List<VideoModel> videos = [];
    int processedFiles = 0;

    // Count total unique files first
    int totalFiles = 0;
    for (final folderPath in _scanFolders) {
      final folder = Directory(folderPath);
      if (!await folder.exists()) continue;
      try {
        await for (final entity in folder.list(recursive: true)) {
          if (entity is File && _isVideoFile(entity.path)) {
            // BUG 5 FIX: resolve symlinks before counting
            final realPath = await entity.resolveSymbolicLinks();
            if (!seenRealPaths.contains(realPath)) {
              seenRealPaths.add(realPath);
              totalFiles++;
            }
          }
        }
      } catch (e) {
        print('❌ SCANNER: Error counting $folderPath: $e');
      }
    }

    print('📊 SCANNER: Found $totalFiles unique video files');
    if (totalFiles == 0) return [];

    // Reset for actual scan pass
    seenRealPaths.clear();

    for (final folderPath in _scanFolders) {
      final folder = Directory(folderPath);
      if (!await folder.exists()) continue;
      try {
        await for (final entity in folder.list(recursive: true)) {
          if (entity is File && _isVideoFile(entity.path)) {
            // BUG 5 FIX: skip if we already processed this real path
            final realPath = await entity.resolveSymbolicLinks();
            if (seenRealPaths.contains(realPath)) continue;
            seenRealPaths.add(realPath);

            // Use the real path so the player can open it
            final video = await _processVideoFile(File(realPath));
            if (video != null) {
              videos.add(video);
              await _dbService.insertVideo(video);
            }

            processedFiles++;
            onProgress?.call(processedFiles, totalFiles);
          }
        }
      } catch (e) {
        print('❌ SCANNER: Error scanning $folderPath: $e');
      }
    }

    print('✅ SCANNER: Scan complete — ${videos.length} unique videos');
    return videos;
  }

bool _isVideoFile(String path) {
    final lower = path.toLowerCase();

    // Skip trash, recycle bins, system folders, and MIUI-specific paths
    const blockedSegments = [
      '/.trash',
      '/.trashed',
      '/android/data/',
      '/android/obb/',
      '/.thumbnails',
      '/thumbnail',
      '/miui/gallery/cloud',
      '/.nomedia',
      '/com.miui.gallery',
      '/com.xiaomi',
      '/.recycle',
      '/recently_deleted',
      '/miui/.gallery_data',
      '/alarms/',
      '/ringtones/',
      '/notifications/',
      '/bluetooth/',
      '/.tmp',
      '/.temp',
    ];

    if (blockedSegments.any((seg) => lower.contains(seg))) return false;

    // Skip MIUI trash files — named like ".trashed-1234567890-filename.mp4"
    final filename = lower.split('/').last;
    if (filename.startsWith('.trashed-') || filename.startsWith('.trash-')) return false;

    // Skip files starting with dot (hidden system files)
    if (filename.startsWith('.')) return false;

    final ext = lower.contains('.') ? '.${lower.split('.').last}' : '';
    return _videoExtensions.contains(ext);
  }
  Future<VideoModel?> _processVideoFile(File file) async {
    try {
      final filePath = file.path;
      final fileSize = await file.length();
      final dateAdded = await file.lastModified();

      final parsed = FileNameParser.parseFileName(filePath);
      final videoId = FileNameParser.generateVideoId(filePath);
      final category = FileNameParser.determineCategory(filePath);

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
      print('❌ SCANNER: Error processing ${file.path}: $e');
      return null;
    }
  }

  Future<List<VideoModel>> quickScan() async {
    final existingVideos = await _dbService.getAllVideos();
    // Resolve existing paths to real paths for accurate dedup comparison
    final existingPaths = <String>{};
    for (final v in existingVideos) {
      existingPaths.add(v.filePath);
      try {
        final real = await File(v.filePath).resolveSymbolicLinks();
        existingPaths.add(real);
      } catch (_) {}
    }

    final Set<String> seenRealPaths = {};
    final List<VideoModel> newVideos = [];

    for (final folderPath in _scanFolders) {
      final folder = Directory(folderPath);
      if (!await folder.exists()) continue;
      try {
        await for (final entity in folder.list(recursive: true)) {
          if (entity is File && _isVideoFile(entity.path)) {
            final realPath = await entity.resolveSymbolicLinks();
            if (seenRealPaths.contains(realPath)) continue;
            seenRealPaths.add(realPath);

            if (!existingPaths.contains(realPath)) {
              final video = await _processVideoFile(File(realPath));
              if (video != null) {
                newVideos.add(video);
                await _dbService.insertVideo(video);
              }
            }
          }
        }
      } catch (e) {
        print('❌ SCANNER: Error in quickScan for $folderPath: $e');
      }
    }

    return newVideos;
  }
}