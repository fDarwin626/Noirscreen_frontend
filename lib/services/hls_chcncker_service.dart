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
  String? _cachedVideoCodec; // probe once, reuse for all chunks

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

    _videoPath = await _prepareVideoPath(videoPath);
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
    // Reset any Stale FFmpeg before each session tick to prevent memory leaks
    FFmpegKit.cancel();

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

      // Upload chunk with up to 3 retries — handles Render connection resets
      bool uploaded = false;
      for (int attempt = 1; attempt <= 3; attempt++) {
        uploaded = await _uploadChunk(
          chunkFile: File(chunkPath),
          chunkIndex: i,
        );
        if (uploaded) break;
        if (attempt < 3) {
          print('⚠️ HLS CHUNKER: Retry $attempt for chunk $i');
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      if (uploaded) {
        _lastUploadedChunk = i;
        final file = File(chunkPath);
        if (await file.exists()) await file.delete();
        print('✅ HLS CHUNKER: Chunk $i uploaded and cleaned');
      } else {
        print('❌ HLS CHUNKER: Upload failed for chunk $i after 3 attempts — will retry next tick');
        break;
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

  // Use cached codec — probing every chunk wastes 200-400ms per chunk
  if (_cachedVideoCodec == null) {
    try {
      final probeSession = await FFprobeKit.getMediaInformation(inputPath);
      final info = probeSession.getMediaInformation();
      if (info != null) {
        final streams = info.getStreams();
        if (streams != null) {
          for (final stream in streams) {
            if (stream.getType()?.toLowerCase() == 'video') {
              _cachedVideoCodec = stream.getCodec()?.toLowerCase() ?? 'unknown';
              break;
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ HLS CHUNKER: Codec probe failed - $e');
    }
    _cachedVideoCodec ??= 'unknown';
    print('🎬 HLS CHUNKER: Detected video codec = $_cachedVideoCodec');
  }
  final String videoCodec = _cachedVideoCodec!;
  // Step 2: Choose command based on codec
  // H.264 → copy stream + h264_mp4toannexb filter (converts MP4 to MPEG-TS bitstream)
  // HEVC/H.265 → copy stream + hevc_mp4toannexb filter (same idea, correct filter)
  // Unknown/other → re-encode to H.264 (slowest but guaranteed to work)
  String command;

  if (videoCodec.contains('h264') || videoCodec.contains('avc')) {
    // H.264 — fast copy with correct bsf
    command =
        '-ss $startSeconds '
        '-i "$inputPath" '
        '-t $durationSeconds '
        '-c copy '
        '-bsf:v h264_mp4toannexb '
        '-f mpegts '
        '"$outputPath"';
    print('✅ HLS CHUNKER: Using H.264 copy path');
  } else if (videoCodec.contains('hevc') || videoCodec.contains('h265') || videoCodec.contains('265')) {
    // HEVC/H.265 — fast copy with hevc_mp4toannexb
    command =
        '-ss $startSeconds '
        '-i "$inputPath" '
        '-t $durationSeconds '
        '-c copy '
        '-bsf:v hevc_mp4toannexb '
        '-f mpegts '
        '"$outputPath"';
    print('✅ HLS CHUNKER: Using HEVC copy path');
  } else {
    // Unknown codec — re-encode to H.264 baseline
    // Slower but works for AV1, VP9, or anything exotic
    command =
        '-ss $startSeconds '
        '-i "$inputPath" '
        '-t $durationSeconds '
        '-c:v libx264 -preset ultrafast -crf 28 '
        '-c:a aac -b:a 128k '
        '-f mpegts '
        '"$outputPath"';
    print('⚠️ HLS CHUNKER: Unknown codec — re-encoding to H.264');
  }

  final session = await FFmpegKit.execute(command);
  final returnCode = await session.getReturnCode();

  if (ReturnCode.isSuccess(returnCode)) return true;

  // Step 3: First attempt failed — last resort full re-encode
  // This catches edge cases like corrupted headers or unusual container quirks
  print('⚠️ HLS CHUNKER: First attempt failed, trying full re-encode as last resort...');
  if (await File(outputPath).exists()) await File(outputPath).delete();

  final fallbackCommand =
      '-ss $startSeconds '
      '-i "$inputPath" '
      '-t $durationSeconds '
      '-c:v libx264 -preset ultrafast -crf 28 '
      '-c:a aac -b:a 128k '
      '-f mpegts '
      '"$outputPath"';

  final session2 = await FFmpegKit.execute(fallbackCommand);
  final returnCode2 = await session2.getReturnCode();

  if (!ReturnCode.isSuccess(returnCode2)) {
    final logs = await session2.getAllLogs();
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

Future<String> _prepareVideoPath(String inputPath) async {
  // Only remux MKV — MP4 and others go straight to chunking
  if (!inputPath.toLowerCase().endsWith('.mkv')) return inputPath;

  final appDir = await getTemporaryDirectory();
  final remuxPath = '${appDir.path}/remuxed_${_roomId}.mp4';
  if (File(remuxPath).existsSync()) return remuxPath;

  print('🔄 HLS CHUNKER: Remuxing MKV → MP4 (keeping original codec)...');

  // -c copy keeps HEVC/H.264/AAC streams untouched — just changes container
  final cmd = '-i "$inputPath" -c:v copy -c:a aac -b:a 128k -movflags faststart -f mp4 "$remuxPath"';
  final session = await FFmpegKit.execute(cmd);
  final rc = await session.getReturnCode();

  if (ReturnCode.isSuccess(rc)) {
    print('✅ HLS CHUNKER: Remux complete → $remuxPath');
    return remuxPath;
  }
  print('⚠️ HLS CHUNKER: Remux failed, using original MKV path');
  return inputPath;
}

  // ── Stop chunking — called when room ends ─────────────────────────────────
  Future<void> stop() async {
    _isRunning = false;
    _cachedVideoCodec = null; // reset for next session
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