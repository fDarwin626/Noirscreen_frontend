import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'api_services.dart';

class HlsChunkerService {
  // How many seconds of chunks to keep uploaded ahead of current playback.
  // 60 seconds = comfortable buffer without wasting server storage.
  // At any moment the server holds at most ~15–20MB per room.
  static const int _bufferAheadSeconds = 60;

  // Each chunk is 3 seconds — standard HLS segment size.
  // Small enough for fast upload, large enough to reduce HTTP overhead.
  static const int _chunkDurationSeconds = 3;

  String? _roomId;
  String? _videoPath;
  Timer? _uploadTimer;
  bool _isRunning = false;

  // Tracks the highest chunk index we have uploaded so far
  int _lastUploadedChunk = -1;

  // Total duration of the video in seconds
  int _totalDurationSeconds = 0;

  // Temp folder on device where chunks are written before upload
  String? _chunkDir;

  // ── Start chunking for a room ─────────────────────────────────────────────
  // Call this when the owner presses go on a room.
  // videoPath = full local path to the video file
  // roomId    = the room UUID from backend
  // onError   = callback if something goes wrong
  Future<void> start({
    required String videoPath,
    required String roomId,
    required void Function(String error) onError,
  }) async {
    if (_isRunning) return;

    // Security: validate path before touching anything
    if (!_isValidPath(videoPath)) {
      onError('Invalid video file path');
      return;
    }

    _videoPath = videoPath;
    _roomId = roomId;
    _isRunning = true;

    // Create temp directory for this room's chunks on device
    final appDir = await getTemporaryDirectory();
    _chunkDir = '${appDir.path}/hls_chunks/$roomId';
    await Directory(_chunkDir!).create(recursive: true);

    // Step 1: Get total video duration using FFprobe
    // We need this to know when to stop chunking
    _totalDurationSeconds = await _getVideoDuration(videoPath);
    if (_totalDurationSeconds == 0) {
      onError('Could not read video duration');
      _isRunning = false;
      return;
    }
    print('📽️ HLS CHUNKER: Video is ${_totalDurationSeconds}s long');

    // Step 2: Pre-generate and upload the first 60 seconds immediately
    // so viewers can start loading as soon as the room goes live
    await _chunkAndUploadRange(
      fromChunk: 0,
      toChunk: (_bufferAheadSeconds ~/ _chunkDurationSeconds) - 1,
    );

    // Step 3: Every 10 seconds check playback position and upload the
    // next batch of chunks, deleting old ones behind playback
    _uploadTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _tick(),
    );

    print('✅ HLS CHUNKER: Started for room $roomId');
  }

  // ── Tick — called every 10 seconds ───────────────────────────────────────
  // Gets current playback position from backend and ensures
  // the next 60 seconds of chunks are always ready
  Future<void> _tick() async {
    if (!_isRunning || _videoPath == null || _roomId == null) return;

    try {
      final positionSeconds = await _getCurrentPosition();
      final currentChunk = positionSeconds ~/ _chunkDurationSeconds;

      // We want to always be 60s ahead of wherever playback is now
      final targetChunk =
          currentChunk + (_bufferAheadSeconds ~/ _chunkDurationSeconds);

      if (targetChunk > _lastUploadedChunk) {
        await _chunkAndUploadRange(
          fromChunk: _lastUploadedChunk + 1,
          toChunk: targetChunk,
        );
      }

      // Delete chunks that playback has already passed
      // This is the rolling window — keeps server storage tiny
      if (currentChunk > 1) {
        await _deleteOldChunksOnServer(currentChunk - 1);
      }
    } catch (e) {
      print('❌ HLS CHUNKER: Tick error - $e');
    }
  }

  // ── Chunk a range of the video and upload each chunk ─────────────────────
  Future<void> _chunkAndUploadRange({
    required int fromChunk,
    required int toChunk,
  }) async {
    if (_chunkDir == null || _videoPath == null) return;

    for (int i = fromChunk; i <= toChunk; i++) {
      if (!_isRunning) break;

      final startSeconds = i * _chunkDurationSeconds;
      if (startSeconds >= _totalDurationSeconds) break;

      final chunkPath =
          '$_chunkDir/chunk_${i.toString().padLeft(5, '0')}.ts';

      // Generate this single chunk using ffmpeg
      final success = await _generateChunk(
        inputPath: _videoPath!,
        outputPath: chunkPath,
        startSeconds: startSeconds,
        durationSeconds: _chunkDurationSeconds,
      );

      if (!success) {
        print('❌ HLS CHUNKER: Failed to generate chunk $i');
        continue;
      }

      // Upload chunk to backend
      final uploaded = await _uploadChunk(
        chunkFile: File(chunkPath),
        chunkIndex: i,
      );

      if (uploaded) {
        _lastUploadedChunk = i;
        // Delete local chunk after upload — saves device storage
        final file = File(chunkPath);
        if (await file.exists()) await file.delete();
        print('✅ HLS CHUNKER: Chunk $i uploaded and cleaned');
      } else {
        print('❌ HLS CHUNKER: Upload failed for chunk $i — will retry');
        break; // Stop and retry on next tick
      }
    }
  }

  // ── Generate one .ts chunk using ffmpeg_kit ───────────────────────────────
  // -ss = start position in the video
  // -t  = duration to extract
  // -c copy = NO re-encoding — just splitting at keyframes
  //           This is what keeps the phone cool and battery healthy.
  //           Re-encoding would be 10x more CPU intensive.
  Future<bool> _generateChunk({
    required String inputPath,
    required String outputPath,
    required int startSeconds,
    required int durationSeconds,
  }) async {
    final command =
        '-ss $startSeconds '
        '-i "$inputPath" '
        '-t $durationSeconds '
        '-c copy '
        '-f mpegts '
        '"$outputPath"';

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogs();
      for (final log in logs) {
        print('ffmpeg: ${log.getMessage()}');
      }
      return false;
    }

    return true;
  }

  // ── Upload a chunk file to the backend ────────────────────────────────────
  Future<bool> _uploadChunk({
    required File chunkFile,
    required int chunkIndex,
  }) async {
    try {
      final uri = Uri.parse(
        '${ApiService.baseUrl}/api/rooms/$_roomId/chunk',
      );
      final request = http.MultipartRequest('POST', uri);
      request.fields['chunkIndex'] = chunkIndex.toString();
      request.files.add(
        await http.MultipartFile.fromPath(
          'chunk',
          chunkFile.path,
          filename:
              'chunk_${chunkIndex.toString().padLeft(5, '0')}.ts',
        ),
      );

      final response = await request.send();
      return response.statusCode == 200;
    } catch (e) {
      print('❌ HLS CHUNKER: Upload error - $e');
      return false;
    }
  }

  // ── Tell backend to delete chunks behind current playback ─────────────────
  Future<void> _deleteOldChunksOnServer(int upToChunkIndex) async {
    try {
      await http.delete(
        Uri.parse(
          '${ApiService.baseUrl}/api/rooms/$_roomId/chunks/before/$upToChunkIndex',
        ),
      );
    } catch (e) {
      print('❌ HLS CHUNKER: Delete old chunks error - $e');
    }
  }

  // ── Ask backend for current playback position ─────────────────────────────
  // Backend tracks this via room_play/room_seek socket events
  Future<int> _getCurrentPosition() async {
    try {
      final res = await http.get(
        Uri.parse(
          '${ApiService.baseUrl}/api/rooms/$_roomId/position',
        ),
      );
      if (res.statusCode == 200) {
        return int.tryParse(res.body.trim()) ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  // ── Get video duration using FFprobe ──────────────────────────────────────
  Future<int> _getVideoDuration(String videoPath) async {
    try {
      final session =
          await FFprobeKit.getMediaInformation(videoPath);
      final info = session.getMediaInformation();
      if (info == null) return 0;

      final duration = info.getDuration();
      if (duration == null) return 0;

      return double.tryParse(duration)?.toInt() ?? 0;
    } catch (e) {
      print('❌ HLS CHUNKER: Duration error - $e');
      return 0;
    }
  }

  // ── Security: validate file path ─────────────────────────────────────────
  bool _isValidPath(String path) {
    if (!path.startsWith('/')) return false;
    if (path.contains('..')) return false;
    const allowed = [
      '/storage/emulated/0/',
      '/sdcard/',
      '/data/user/',
    ];
    if (!allowed.any((r) => path.startsWith(r))) return false;
    const exts = ['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv'];
    return exts.contains(path.split('.').last.toLowerCase());
  }

  // ── Stop chunking — called when room ends ─────────────────────────────────
  Future<void> stop() async {
    _isRunning = false;
    _uploadTimer?.cancel();

    // Delete local chunks folder on device
    if (_chunkDir != null) {
      final dir = Directory(_chunkDir!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }

    // Tell backend to delete ALL server-side chunks for this room
    if (_roomId != null) {
      try {
        await http.delete(
          Uri.parse(
            '${ApiService.baseUrl}/api/rooms/$_roomId/chunks/all',
          ),
        );
      } catch (e) {
        print('❌ HLS CHUNKER: Cleanup error - $e');
      }
    }

    print('🛑 HLS CHUNKER: Stopped for room $_roomId');
  }
}