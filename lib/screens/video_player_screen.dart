import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import 'dart:async';
import 'dart:ui';
import '../models/video_model.dart';
import '../models/series_model.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_style.dart';
import '../services/video_database_service.dart';
import '../services/thumbnail_generator_service.dart';
import 'room_video_picker_screen.dart';

class VideoPlayerScreen extends StatefulWidget {
  final VideoModel video;
  final List<VideoModel>? seriesEpisodes;
  final SeriesModel? series;

  const VideoPlayerScreen({
    super.key,
    required this.video,
    this.seriesEpisodes,
    this.series,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';

  late VideoModel _currentVideo;

  bool _showControls = true;
  bool _isExpanded = false;
  bool _isLocked = false;
  bool _showDropdown = false;

  // ── Lock overlay visibility ────────────────────────────────────────────────
  // true = "Tap to unlock" badge is visible
  // Auto-hides after 5s, reappears on tap when locked
  bool _showLockBadge = false;
  Timer? _lockBadgeTimer;

  Timer? _hideControlsTimer;
  Timer? _progressSaveTimer;
  Timer? _countdownTimer;

  final VideoDatabaseService _database = VideoDatabaseService();
  final ThumbnailGeneratorService _thumbnailGenerator =
      ThumbnailGeneratorService();

  VideoModel? _nextEpisode;
  bool _showNextEpisodeCountdown = false;
  int _countdownSeconds = 5;

  @override
  void initState() {
    super.initState();
    _currentVideo = widget.video;
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initPlayer();
    _resolveNextEpisode();
  }

  bool _isValidVideoPath(String path) {
    if (!path.startsWith('/')) return false;
    const allowedRoots = [
      '/storage/emulated/0/',
      '/sdcard/',
      '/data/user/',
    ];
    if (!allowedRoots.any((r) => path.startsWith(r))) return false;
    if (path.contains('..')) return false;
    const validExt = [
      'mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv', 'm4v', '3gp'
    ];
    return validExt.contains(path.toLowerCase().split('.').last);
  }

  Future<void> _initPlayer() async {
    try {
      if (!_isValidVideoPath(_currentVideo.filePath)) {
        if (mounted) setState(() {
          _hasError = true;
          _errorMessage = 'Invalid video file path';
        });
        return;
      }

      final file = File(_currentVideo.filePath);
      if (!await file.exists()) {
        if (mounted) setState(() {
          _hasError = true;
          _errorMessage = 'Video file not found on device';
        });
        return;
      }

      await _controller?.dispose();

      final controller = VideoPlayerController.file(file);
      _controller = controller;

      await controller.initialize();

      controller.addListener(_onPlayerUpdate);
      await controller.play();

      if ((_currentVideo.watchProgress ?? 0) > 0) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          await controller.seekTo(
            Duration(seconds: _currentVideo.watchProgress!),
          );
        }
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
        });
      }

      _startProgressSaveTimer();
      _resetHideControlsTimer();
    } catch (e) {
      if (mounted) setState(() {
        _hasError = true;
        _errorMessage = 'Could not play this video';
      });
    }
  }

  void _onPlayerUpdate() {
    if (_controller == null || !mounted) return;
    final pos = _controller!.value.position;
    final dur = _controller!.value.duration;
    if (dur.inSeconds > 0 && pos >= dur) _onVideoCompleted();
    if (mounted) setState(() {});
  }

  void _onVideoCompleted() async {
    await _saveProgress(markCompleted: true);
    if (_nextEpisode != null) {
      setState(() {
        _showNextEpisodeCountdown = true;
        _countdownSeconds = 5;
      });
      _startCountdown();
    } else {
      setState(() => _showControls = true);
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_countdownSeconds <= 1) {
        timer.cancel();
        _playNextEpisode();
      } else {
        setState(() => _countdownSeconds--);
      }
    });
  }

  void _playNextEpisode() {
    if (_nextEpisode == null) return;
    setState(() {
      _currentVideo = _nextEpisode!;
      _isInitialized = false;
      _hasError = false;
      _showNextEpisodeCountdown = false;
      _countdownSeconds = 5;
      _isLocked = false;
      _showDropdown = false;
      _showLockBadge = false;
    });
    _lockBadgeTimer?.cancel();
    _resolveNextEpisode();
    _initPlayer();
  }

  void _resolveNextEpisode() {
    if (widget.seriesEpisodes == null || widget.seriesEpisodes!.isEmpty) {
      _nextEpisode = null;
      return;
    }
    final episodes = widget.seriesEpisodes!;
    final idx = episodes.indexWhere((e) => e.id == _currentVideo.id);
    _nextEpisode = (idx == -1 || idx == episodes.length - 1)
        ? null
        : episodes[idx + 1];
  }

  Future<void> _saveProgress({bool markCompleted = false}) async {
    if (_controller == null) return;
    final position = _controller!.value.position.inSeconds;
    final duration = _controller!.value.duration.inSeconds;
    if (duration == 0) return;

    final isCompleted =
        markCompleted || (duration > 0 && (position / duration) >= 0.9);

    String? resumeThumbnailPath;
    if (!isCompleted && position > 5) {
      try {
        resumeThumbnailPath =
            await _thumbnailGenerator.generateResumeThumbnail(
          _currentVideo.copyWith(watchProgress: position),
        );
      } catch (e) {
        // silent
      }
    }

    final updated = _currentVideo.copyWith(
      watchProgress: isCompleted ? 0 : position,
      isCompleted: isCompleted,
      lastWatched: DateTime.now(),
      watchCount: isCompleted
          ? (_currentVideo.watchCount + 1)
          : _currentVideo.watchCount,
      thumbnailPath: resumeThumbnailPath ?? _currentVideo.thumbnailPath,
    );

    await _database.updateVideo(updated);
    _currentVideo = updated;
  }

  void _startProgressSaveTimer() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _saveProgress(),
    );
  }

  void _resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() {
          _showControls = false;
          _showDropdown = false;
        });
      }
    });
  }

  // ── Show lock badge for 5s then auto-hide ──────────────────────────────────
  void _showLockBadgeTemporarily() {
    _lockBadgeTimer?.cancel();
    setState(() => _showLockBadge = true);
    _lockBadgeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showLockBadge = false);
    });
  }

  void _onScreenTap() {
    // When locked, tapping shows the badge temporarily instead of controls
    if (_isLocked) {
      _showLockBadgeTemporarily();
      return;
    }
    setState(() {
      _showControls = !_showControls;
      if (!_showControls) _showDropdown = false;
    });
    if (_showControls) _resetHideControlsTimer();
  }

  void _togglePlayPause() {
    if (_controller == null || _isLocked) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      _hideControlsTimer?.cancel();
    } else {
      _controller!.play();
      _resetHideControlsTimer();
    }
    setState(() {});
  }

  void _seekForward() {
    if (_controller == null || _isLocked) return;
    final newPos = _controller!.value.position + const Duration(seconds: 10);
    _controller!.seekTo(newPos);
    _resetHideControlsTimer();
  }

  void _seekBackward() {
    if (_controller == null || _isLocked) return;
    final newPos = _controller!.value.position - const Duration(seconds: 10);
    _controller!.seekTo(newPos < Duration.zero ? Duration.zero : newPos);
    _resetHideControlsTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _controller?.pause();
      _saveProgress();
    }
  }

  @override
  void dispose() {
    _saveProgress();
    _hideControlsTimer?.cancel();
    _progressSaveTimer?.cancel();
    _countdownTimer?.cancel();
    _lockBadgeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onPlayerUpdate);
    _controller?.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: GestureDetector(
        onTap: _onScreenTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoSurface(),
            if (!_isLocked && _showControls && _isInitialized && !_hasError)
              _buildControlsOverlay(),
            // Lock badge — only rendered when locked AND badge is visible
            if (_isLocked && _showLockBadge) _buildLockOverlay(),
            if (!_isInitialized && !_hasError) _buildLoadingOverlay(),
            if (_hasError) _buildErrorOverlay(),
            if (_showNextEpisodeCountdown && !_isLocked)
              _buildNextEpisodeOverlay(),
            if (_showDropdown && !_isLocked) _buildDropdownMenu(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSurface() {
    if (!_isInitialized || _controller == null) {
      return Container(color: AppColors.black);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final sw = constraints.maxWidth;
        final sh = constraints.maxHeight;
        final va = _controller!.value.aspectRatio;

        if (_isExpanded) {
          return SizedBox(
            width: sw,
            height: sh,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: sw,
                height: sw / va,
                child: VideoPlayer(_controller!),
              ),
            ),
          );
        }

        double vw = sw;
        double vh = sw / va;
        if (vh > sh) { vh = sh; vw = sh * va; }

        return Container(
          color: AppColors.black,
          width: sw,
          height: sh,
          child: Center(
            child: SizedBox(
              width: vw,
              height: vh,
              child: VideoPlayer(_controller!),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlsOverlay() {
    final controller = _controller!;
    final position = controller.value.position;
    final duration = controller.value.duration;
    final isPlaying = controller.value.isPlaying;

    return AnimatedOpacity(
      opacity: _showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.black.withOpacity(0.7),
              Colors.transparent,
              Colors.transparent,
              AppColors.black.withOpacity(0.8),
            ],
            stops: const [0.0, 0.2, 0.7, 1.0],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 16,
              left: 8,
              right: 12,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_rounded,
                        color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.series != null)
                          Text(widget.series!.title,
                              style: AppTextStyles.caption.copyWith(
                                  color: AppColors.ashGray, fontSize: 11)),
                        Text(_currentVideo.title,
                            style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textWhite,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  _buildTopButton(
                    icon: _isExpanded
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    onTap: () {
                      setState(() => _isExpanded = !_isExpanded);
                      _resetHideControlsTimer();
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildTopButton(
                    icon: Icons.more_horiz_rounded,
                    onTap: () {
                      setState(() => _showDropdown = !_showDropdown);
                      _hideControlsTimer?.cancel();
                    },
                  ),
                ],
              ),
            ),

            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildCenterButton(
                      icon: Icons.replay_10_rounded, onTap: _seekBackward),
                  const SizedBox(width: 40),
                  GestureDetector(
                    onTap: _togglePlayPause,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: AppColors.niorRed),
                      child: Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 36),
                    ),
                  ),
                  const SizedBox(width: 40),
                  _buildCenterButton(
                      icon: Icons.forward_10_rounded, onTap: _seekForward),
                ],
              ),
            ),

            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_currentVideo.seasonEpisode != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_currentVideo.seasonEpisode!,
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.ashGray, fontSize: 11)),
                    ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      trackHeight: 3,
                      activeTrackColor: AppColors.niorRed,
                      inactiveTrackColor: AppColors.ashGray.withOpacity(0.3),
                      thumbColor: AppColors.niorRed,
                      overlayColor: AppColors.niorRed.withOpacity(0.2),
                    ),
                    child: Slider(
                      value: duration.inSeconds > 0
                          ? position.inSeconds
                              .clamp(0, duration.inSeconds)
                              .toDouble()
                          : 0.0,
                      min: 0,
                      max: duration.inSeconds > 0
                          ? duration.inSeconds.toDouble()
                          : 1.0,
                      onChanged: (value) {
                        if (_isLocked) return;
                        _controller!
                            .seekTo(Duration(seconds: value.toInt()));
                        _resetHideControlsTimer();
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(position),
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.textWhite, fontSize: 12)),
                      Text(_formatDuration(duration),
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.ashGray, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Lock overlay — auto-hides after 5s, tap screen to show again ───────────
  Widget _buildLockOverlay() {
    return Positioned(
      top: 20,
      right: 16,
      child: AnimatedOpacity(
        opacity: _showLockBadge ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: GestureDetector(
          onTap: () {
            // Tapping the badge itself unlocks
            _lockBadgeTimer?.cancel();
            setState(() {
              _isLocked = false;
              _showLockBadge = false;
              _showControls = true;
            });
            _resetHideControlsTimer();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.black.withOpacity(0.65),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.ashGray.withOpacity(0.25),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, color: AppColors.textWhite, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Tap to unlock',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textWhite,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownMenu() {
    return Positioned(
      top: 60,
      right: 12,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 200,
            decoration: BoxDecoration(
              color: AppColors.black.withOpacity(0.75),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.12),
                width: 0.8,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDropdownItem(
                  icon: Icons.cast_connected_rounded,
                  label: 'Stream Video',
                  onTap: () {
                    setState(() => _showDropdown = false);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RoomVideoPickerScreen(
                          streamType: 'hls',
                          preSelectedVideo: _currentVideo,
                        ),
                      ),
                    );
                  },
                ),
                Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Colors.white.withOpacity(0.08),
                ),
                _buildDropdownItem(
                  icon: Icons.lock_rounded,
                  label: 'Lock screen',
                  onTap: () {
                    setState(() {
                      _showDropdown = false;
                      _showControls = false;
                      _isLocked = true;
                    });
                    _hideControlsTimer?.cancel();
                    // Show badge for 5s after locking
                    _showLockBadgeTemporarily();
                  },
                ),
                Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Colors.white.withOpacity(0.08),
                ),
                _buildDropdownItem(
                  icon: _isExpanded
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  label: _isExpanded ? 'Fit to screen' : 'Fill screen',
                  onTap: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                      _showDropdown = false;
                    });
                    _resetHideControlsTimer();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 14),
            Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textWhite,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.black.withOpacity(0.4),
          border: Border.all(
            color: AppColors.ashGray.withOpacity(0.2),
            width: 0.8,
          ),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildCenterButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.black.withOpacity(0.4),
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: AppColors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.niorRed),
            ),
            const SizedBox(height: 16),
            Text('Loading...',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textGray, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: AppColors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: AppColors.error, size: 56),
            const SizedBox(height: 16),
            Text(_errorMessage,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textWhite, fontSize: 15),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.charcoal,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.ashGray.withOpacity(0.2)),
                ),
                child: Text('Go Back',
                    style: AppTextStyles.button.copyWith(fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNextEpisodeOverlay() {
    return Positioned(
      right: 24,
      bottom: 80,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.charcoal.withOpacity(0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.ashGray.withOpacity(0.15), width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('UP NEXT',
                style: AppTextStyles.caption.copyWith(
                    color: AppColors.niorRed,
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(_nextEpisode?.title ?? '',
                style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _playNextEpisode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                          color: AppColors.niorRed,
                          borderRadius: BorderRadius.circular(6)),
                      child: Center(
                        child: Text('Play in ${_countdownSeconds}s',
                            style: AppTextStyles.caption.copyWith(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    _countdownTimer?.cancel();
                    setState(() => _showNextEpisodeCountdown = false);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: AppColors.darkGray,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text('Cancel',
                        style: AppTextStyles.caption.copyWith(
                            color: AppColors.textGray, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}