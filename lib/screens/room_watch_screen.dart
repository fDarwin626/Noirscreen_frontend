import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noirscreen/services/hls_chcncker_service.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import '../constants/app_colors.dart';
import '../models/scheduled_room_model.dart';
import '../models/user_model.dart';
import '../services/room_watch_service.dart';

class RoomParticipant {
  final String userId;
  final String username;
  final String? avatarPath;
  final bool isOwner;
  bool isSpeaking;
  bool isMuted;

  RoomParticipant({
    required this.userId,
    required this.username,
    this.avatarPath,
    this.isOwner = false,
    this.isSpeaking = false,
    this.isMuted = false,
  });
}

// ── Pending join request model (skeleton — wired when Discovery is built) ────
class PendingJoinRequest {
  final String requestId;
  final String userId;
  final String username;
  final String? avatarPath;

  PendingJoinRequest({
    required this.requestId,
    required this.userId,
    required this.username,
    this.avatarPath,
  });
}

class RoomWatchScreen extends ConsumerStatefulWidget {
  final ScheduledRoomModel room;
  final UserModel currentUser;
  final bool isOwner;
  final String? localFilePath;
  final String? hlsStreamUrl;

  const RoomWatchScreen({
    super.key,
    required this.room,
    required this.currentUser,
    required this.isOwner,
    this.localFilePath,
    this.hlsStreamUrl,
  });

  @override
  ConsumerState<RoomWatchScreen> createState() => _RoomWatchScreenState();
}

class _RoomWatchScreenState extends ConsumerState<RoomWatchScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {

  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _videoError = false;
  String _videoErrorMessage = 'Could not load video';

  bool _showControls = true;
  bool _showAvatars = true;

  // ── Same as normal player ─────────────────────────────────────────────────
  bool _isExpanded = false;
  bool _isLocked = false;
  bool _showLockBadge = false;
  Timer? _lockBadgeTimer;

  // ── Dropdown state ────────────────────────────────────────────────────────
  // false = main menu, true = pending requests panel
  bool _showDropdown = false;
  bool _showPendingRequests = false;

  Timer? _hideControlsTimer;
  Timer? _progressTimer;

  RoomWatchService? _watchService;
  bool _serviceConnected = false;

  HlsChunkerService? _chunker;

  final List<RoomParticipant> _participants = [];
  final Map<String, AnimationController> _speakControllers = {};

  // ── Pending requests (skeleton — populated when Discovery is built) ───────
  final List<PendingJoinRequest> _pendingRequests = [];

  // ── Volume & Brightness ───────────────────────────────────────────────────
  double _volume = 15;
  double _brightness = 7;
  static const double _maxVolume = 30;
  static const double _maxBrightness = 15;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _addParticipant(RoomParticipant(
      userId: widget.currentUser.userId,
      username: widget.currentUser.username,
      isOwner: widget.isOwner,
    ));

    _initVideo();
    _initRoomService();
    _resetHideControlsTimer();
  }

  // ── Security ───────────────────────────────────────────────────────────────
  bool _isValidPath(String path) {
    if (!path.startsWith('/')) return false;
    if (path.contains('..')) return false;
    const allowed = ['/storage/emulated/0/', '/sdcard/', '/data/user/'];
    if (!allowed.any((r) => path.startsWith(r))) return false;
    const exts = ['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv'];
    return exts.contains(path.split('.').last.toLowerCase());
  }

  bool _isValidStreamUrl(String url) {
    return (url.startsWith('http://') || url.startsWith('https://'))
        && url.contains('.m3u8');
  }

  // ── Init video ─────────────────────────────────────────────────────────────
  Future<void> _initVideo() async {
    try {
      VideoPlayerController controller;

      if (widget.localFilePath != null) {
        if (!_isValidPath(widget.localFilePath!)) {
          if (mounted) setState(() {
            _videoError = true;
            _videoErrorMessage = 'Invalid file path: ${widget.localFilePath}';
          });
          return;
        }
        final file = File(widget.localFilePath!);
        if (!await file.exists()) {
          if (mounted) setState(() {
            _videoError = true;
            _videoErrorMessage = 'File not found: ${widget.localFilePath}';
          });
          return;
        }
        controller = VideoPlayerController.file(file);
      } else if (widget.hlsStreamUrl != null) {
        if (!_isValidStreamUrl(widget.hlsStreamUrl!)) {
          if (mounted) setState(() {
            _videoError = true;
            _videoErrorMessage = 'Invalid stream URL: ${widget.hlsStreamUrl}';
          });
          return;
        }
        controller = VideoPlayerController.networkUrl(
            Uri.parse(widget.hlsStreamUrl!));
      } else {
        print('❌ ROOM WATCH: No video source');
        print('   streamType: ${widget.room.streamType}');
        print('   localFilePath: ${widget.localFilePath}');
        print('   hlsStreamUrl: ${widget.hlsStreamUrl}');
        print('   isOwner: ${widget.isOwner}');
        if (mounted) setState(() {
          _videoError = true;
          _videoErrorMessage =
              'No video source.\nType: ${widget.room.streamType}\n'
              'localFile: ${widget.localFilePath ?? "null"}\n'
              'hlsUrl: ${widget.hlsStreamUrl ?? "null"}';
        });
        return;
      }

      _videoController = controller;
      await controller.initialize();
      controller.addListener(_onVideoUpdate);

      // Apply initial volume
      await controller.setVolume(_volume / _maxVolume);

      if (widget.isOwner) {
        await controller.play();

        // Start HLS chunking for audio and hls — not needed for sync
        if (widget.room.streamType == 'audio' ||
            widget.room.streamType == 'hls') {
          _chunker = HlsChunkerService();
          _chunker!.start(
            videoPath: widget.localFilePath!,
            roomId: widget.room.roomId,
            onError: (error) => print('❌ CHUNKER: $error'),
          );
          print('✅ ROOM WATCH: HLS chunker started');
        }
      } else {
        await controller.pause();
      }

      if (mounted) setState(() => _videoInitialized = true);

      _progressTimer = Timer.periodic(
          const Duration(seconds: 5), (_) => _saveProgress());
    } catch (e) {
      print('❌ ROOM WATCH: Video init error - $e');
      if (mounted) setState(() {
        _videoError = true;
        _videoErrorMessage = 'Video error: $e';
      });
    }
  }

  // ── Init socket ────────────────────────────────────────────────────────────
  Future<void> _initRoomService() async {
    final service = RoomWatchService(
      roomId: widget.room.roomId,
      userId: widget.currentUser.userId,
      isOwner: widget.isOwner,
    );

    await service.connect(
      onPlay: (pos) {
        if (!mounted) return;
        _videoController?.seekTo(Duration(seconds: pos));
        _videoController?.play();
        if (mounted) setState(() {});
      },
      onPause: (pos) {
        if (!mounted) return;
        _videoController?.seekTo(Duration(seconds: pos));
        _videoController?.pause();
        if (mounted) setState(() {});
      },
      onSeek: (pos) {
        if (!mounted) return;
        _videoController?.seekTo(Duration(seconds: pos));
      },
      onParticipantJoined: (uid, uname, avatar) {
        if (!mounted) return;
        _addParticipant(RoomParticipant(
            userId: uid, username: uname, avatarPath: avatar));
      },
      onParticipantLeft: (uid) {
        if (!mounted) return;
        setState(() {
          _participants.removeWhere((p) => p.userId == uid);
          _speakControllers[uid]?.dispose();
          _speakControllers.remove(uid);
        });
      },
      onSpeaking: (uid, speaking) {
        if (!mounted) return;
        setState(() {
          final idx = _participants.indexWhere((p) => p.userId == uid);
          if (idx == -1) return;
          _participants[idx].isSpeaking = speaking;
          if (speaking) {
            _speakControllers[uid]?.repeat();
          } else {
            _speakControllers[uid]?.stop();
            _speakControllers[uid]?.reset();
          }
        });
      },
      onMuted: (uid) {
        if (!mounted) return;
        setState(() {
          final idx = _participants.indexWhere((p) => p.userId == uid);
          if (idx != -1) _participants[idx].isMuted = true;
        });
      },
      onKicked: (uid) {
        if (uid == widget.currentUser.userId && mounted) {
          _showKickedDialog();
        }
      },
      onRoomEnded: () {
        if (mounted) _showRoomEndedDialog();
      },
    );

    if (mounted) {
      setState(() {
        _watchService = service;
        _serviceConnected = true;
      });
    }
  }

  void _addParticipant(RoomParticipant p) {
    if (_participants.any((e) => e.userId == p.userId)) return;
    setState(() {
      _participants.add(p);
      _speakControllers[p.userId] = AnimationController(
        duration: const Duration(milliseconds: 900),
        vsync: this,
      );
    });
  }

  void _onVideoUpdate() {
    if (mounted) setState(() {});
  }

  void _saveProgress() {
    final pos = _videoController?.value.position.inSeconds ?? 0;
    print('💾 ROOM: Progress at ${pos}s');
  }

  void _resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() {
        _showControls = false;
        _showDropdown = false;
        _showPendingRequests = false;
      });
    });
  }

  void _onScreenTap() {
    if (_isLocked) {
      _showLockBadgeTemporarily();
      return;
    }
    setState(() => _showControls = !_showControls);
    if (_showControls) _resetHideControlsTimer();
  }

  void _showLockBadgeTemporarily() {
    _lockBadgeTimer?.cancel();
    setState(() => _showLockBadge = true);
    _lockBadgeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showLockBadge = false);
    });
  }

  // ── Volume/brightness drag ─────────────────────────────────────────────────
  void _onVolumeDrag(DragUpdateDetails d) {
    final delta = -d.delta.dy * (_maxVolume / 200);
    setState(() => _volume = (_volume + delta).clamp(0, _maxVolume));
    _videoController?.setVolume(_volume / _maxVolume);
    _resetHideControlsTimer();
  }

  void _onBrightnessDrag(DragUpdateDetails d) {
    final delta = -d.delta.dy * (_maxBrightness / 200);
    setState(() => _brightness = (_brightness + delta).clamp(0, _maxBrightness));
    _resetHideControlsTimer();
  }

  void _play() {
    if (!widget.isOwner || _videoController == null) return;
    final pos = _videoController!.value.position.inSeconds;
    _videoController!.play();
    _watchService?.sendPlay(pos);
    _resetHideControlsTimer();
    setState(() {});
  }

  void _pause() {
    if (!widget.isOwner || _videoController == null) return;
    final pos = _videoController!.value.position.inSeconds;
    _videoController!.pause();
    _watchService?.sendPause(pos);
    _hideControlsTimer?.cancel();
    setState(() {});
  }

  void _seekForward() {
    if (!widget.isOwner || _videoController == null) return;
    final newPos = _videoController!.value.position + const Duration(seconds: 10);
    _videoController!.seekTo(newPos);
    _watchService?.sendSeek(newPos.inSeconds);
    _resetHideControlsTimer();
  }

  void _seekBackward() {
    if (!widget.isOwner || _videoController == null) return;
    final raw = _videoController!.value.position - const Duration(seconds: 10);
    final clamped = raw < Duration.zero ? Duration.zero : raw;
    _videoController!.seekTo(clamped);
    _watchService?.sendSeek(clamped.inSeconds);
    _resetHideControlsTimer();
  }

  void _stopRoom() {
    if (!widget.isOwner) return;
    _watchService?.sendRoomEnd();
    _chunker?.stop();
    Navigator.pop(context);
  }

  void _muteParticipant(String uid) {
    if (!widget.isOwner) return;
    _watchService?.sendMute(uid);
    setState(() {
      final idx = _participants.indexWhere((p) => p.userId == uid);
      if (idx != -1) _participants[idx].isMuted = true;
    });
  }

  // ── Pending request actions (skeleton) ────────────────────────────────────
  void _acceptRequest(PendingJoinRequest req) {
    // TODO: wire to Discovery backend when built
    // _watchService?.sendJoinApproval(req.requestId, req.userId);
    setState(() => _pendingRequests.removeWhere((r) => r.requestId == req.requestId));
    print('✅ ROOM: Accepted ${req.username}');
  }

  void _rejectRequest(PendingJoinRequest req) {
    // TODO: wire to Discovery backend when built
    // _watchService?.sendJoinRejection(req.requestId, req.userId);
    setState(() => _pendingRequests.removeWhere((r) => r.requestId == req.requestId));
    print('❌ ROOM: Rejected ${req.username}');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _videoController?.pause();
      _saveProgress();
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _progressTimer?.cancel();
    _lockBadgeTimer?.cancel();
    _videoController?.removeListener(_onVideoUpdate);
    _videoController?.dispose();
    for (final c in _speakControllers.values) c.dispose();
    _watchService?.disconnect();
    _chunker?.stop();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual, overlays: SystemUiOverlay.values);
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _onScreenTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoSurface(),

            // Brightness drag zone — left third
            Positioned(
              left: 0, top: 0, bottom: 0,
              width: MediaQuery.of(context).size.width / 3,
              child: GestureDetector(
                onVerticalDragUpdate: _onBrightnessDrag,
                onVerticalDragStart: (_) {},
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),

            // Volume drag zone — right third
            Positioned(
              right: 0, top: 0, bottom: 0,
              width: MediaQuery.of(context).size.width / 3,
              child: GestureDetector(
                onVerticalDragUpdate: _onVolumeDrag,
                onVerticalDragStart: (_) {},
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),

            if (_showControls && _videoInitialized && !_videoError && !_isLocked)
              _buildControlsOverlay(),

            // Volume cylinder
            if (_showControls && _videoInitialized && !_videoError && !_isLocked)
              _buildVolumeCylinder(screenHeight),

            // Brightness cylinder
            if (_showControls && _videoInitialized && !_videoError && !_isLocked)
              _buildBrightnessCylinder(screenHeight),

            if (_showAvatars && _participants.isNotEmpty)
              _buildAvatarPanel(),

            if (_videoInitialized && !_videoError)
              _buildAvatarToggle(),

            if (!_videoInitialized && !_videoError)
              _buildLoadingOverlay(),

            if (_videoError) _buildErrorOverlay(),

            if (!_serviceConnected && !_videoError)
              _buildConnectingBadge(),

            if (_isLocked && _showLockBadge) _buildLockOverlay(),

            if (_showDropdown && !_isLocked) _buildDropdownMenu(),
          ],
        ),
      ),
    );
  }

  // ── Volume cylinder ────────────────────────────────────────────────────────
  Widget _buildVolumeCylinder(double screenHeight) {
    final fillFraction = _volume / _maxVolume;
    final cylinderHeight = screenHeight * 0.35;
    final filledHeight = cylinderHeight * fillFraction;

    return Positioned(
      right: 12,
      top: (screenHeight - cylinderHeight) / 2,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          width: 36,
          height: cylinderHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withOpacity(0.10),
            border: Border.all(color: Colors.white.withOpacity(0.20), width: 0.8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  height: filledHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [AppColors.niorRed, AppColors.niorRed.withOpacity(0.7)],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    _volume.toInt().toString(),
                    style: const TextStyle(
                      fontFamily: 'Inter', color: Colors.white,
                      fontSize: 11, fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  child: Icon(
                    _volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: Colors.white.withOpacity(0.7), size: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Brightness cylinder ────────────────────────────────────────────────────
  Widget _buildBrightnessCylinder(double screenHeight) {
    final fillFraction = _brightness / _maxBrightness;
    final cylinderHeight = screenHeight * 0.35;
    final filledHeight = cylinderHeight * fillFraction;

    return Positioned(
      left: 12,
      top: (screenHeight - cylinderHeight) / 2,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          width: 36,
          height: cylinderHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withOpacity(0.10),
            border: Border.all(color: Colors.white.withOpacity(0.20), width: 0.8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  height: filledHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [AppColors.niorRed, AppColors.niorRed.withOpacity(0.7)],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    _brightness.toInt().toString(),
                    style: const TextStyle(
                      fontFamily: 'Inter', color: Colors.white,
                      fontSize: 11, fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  child: Icon(
                    Icons.brightness_6_rounded,
                    color: Colors.white.withOpacity(0.7), size: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Video surface ──────────────────────────────────────────────────────────
  Widget _buildVideoSurface() {
    if (!_videoInitialized || _videoController == null) {
      return Container(color: Colors.black);
    }
    return LayoutBuilder(builder: (context, constraints) {
      final sw = constraints.maxWidth;
      final sh = constraints.maxHeight;
      final va = _videoController!.value.aspectRatio;

      if (_isExpanded) {
        return SizedBox(
          width: sw, height: sh,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: sw, height: sw / va,
              child: VideoPlayer(_videoController!),
            ),
          ),
        );
      }

      double vw = sw;
      double vh = sw / va;
      if (vh > sh) { vh = sh; vw = sh * va; }
      return Container(
        color: Colors.black,
        child: Center(
          child: SizedBox(width: vw, height: vh, child: VideoPlayer(_videoController!)),
        ),
      );
    });
  }

  // ── Controls overlay ───────────────────────────────────────────────────────
  Widget _buildControlsOverlay() {
    final ctrl = _videoController!;
    final pos = ctrl.value.position;
    final dur = ctrl.value.duration;
    final playing = ctrl.value.isPlaying;

    return AnimatedOpacity(
      opacity: _showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.65),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withOpacity(0.75),
            ],
            stops: const [0.0, 0.18, 0.72, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // ── Top bar ────────────────────────────────────────────
            Positioned(
              top: 16, left: 12, right: 16,
              child: Row(
                children: [
                  _glassBtn(icon: Icons.arrow_back_ios_new_rounded, onTap: _confirmLeave),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.room.videoTitle,
                          style: const TextStyle(
                            fontFamily: 'BebasNeue', color: Colors.white,
                            fontSize: 18, letterSpacing: 1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _streamTypeLabel(widget.room.streamType),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _participantBadge(),
                  const SizedBox(width: 8),
                  // Fill/fit toggle
                  _glassBtn(
                    icon: _isExpanded
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    onTap: () {
                      setState(() => _isExpanded = !_isExpanded);
                      _resetHideControlsTimer();
                    },
                  ),
                  const SizedBox(width: 8),
                  // Three dots dropdown
                  _glassBtn(
                    icon: Icons.more_horiz_rounded,
                    onTap: () {
                      setState(() {
                        _showDropdown = !_showDropdown;
                        _showPendingRequests = false;
                      });
                      _hideControlsTimer?.cancel();
                    },
                  ),
                  if (widget.isOwner) ...[
                    const SizedBox(width: 8),
                    _glassBtn(
                      icon: Icons.stop_circle_outlined,
                      onTap: _stopRoom,
                      color: AppColors.error,
                    ),
                  ],
                ],
              ),
            ),

            // ── Center: owner controls / viewer label ──────────────
            if (widget.isOwner)
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _centerBtn(icon: Icons.replay_10_rounded, onTap: _seekBackward),
                    const SizedBox(width: 36),
                    GestureDetector(
                      onTap: playing ? _pause : _play,
                      child: Container(
                        width: 60, height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.15),
                          border: Border.all(color: Colors.white.withOpacity(0.3), width: 0.8),
                        ),
                        child: Icon(
                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white, size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(width: 36),
                    _centerBtn(icon: Icons.forward_10_rounded, onTap: _seekForward),
                  ],
                ),
              ),

            if (!widget.isOwner)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8),
                  ),
                  child: Text(
                    'Controlled by host',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white.withOpacity(0.40),
                      fontSize: 11,
                    ),
                  ),
                ),
              ),

            // ── Progress bar ───────────────────────────────────────
            Positioned(
              left: 16, right: 16, bottom: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: widget.isOwner
                          ? const RoundSliderThumbShape(enabledThumbRadius: 6)
                          : const RoundSliderThumbShape(enabledThumbRadius: 0),
                      trackHeight: 2.5,
                      activeTrackColor: AppColors.niorRed,
                      inactiveTrackColor: Colors.white.withOpacity(0.15),
                      thumbColor: Colors.white,
                      overlayColor: AppColors.niorRed.withOpacity(0.15),
                    ),
                    child: Slider(
                      value: dur.inSeconds > 0
                          ? pos.inSeconds.clamp(0, dur.inSeconds).toDouble()
                          : 0.0,
                      min: 0,
                      max: dur.inSeconds > 0 ? dur.inSeconds.toDouble() : 1.0,
                      onChanged: widget.isOwner
                          ? (val) {
                              final p = Duration(seconds: val.toInt());
                              _videoController!.seekTo(p);
                              _watchService?.sendSeek(val.toInt());
                              _resetHideControlsTimer();
                            }
                          : null,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(pos),
                          style: TextStyle(fontFamily: 'Inter',
                              color: Colors.white.withOpacity(0.7), fontSize: 11)),
                      Text(_fmt(dur),
                          style: TextStyle(fontFamily: 'Inter',
                              color: Colors.white.withOpacity(0.30), fontSize: 11)),
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

  String _streamTypeLabel(String type) {
    switch (type) {
      case 'audio': return 'Audio Stream';
      case 'hls':   return 'Video Stream';
      case 'sync':  return 'Sync Watch';
      default:      return 'Stream';
    }
  }

  // ── Dropdown menu ─────────────────────────────────────────────────────────
  // Animates between main menu and pending requests panel
  Widget _buildDropdownMenu() {
    return Positioned(
      top: 60, right: 12,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 220,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.80),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _showPendingRequests
                  ? _buildPendingRequestsPanel()
                  : _buildMainDropdownItems(),
            ),
          ),
        ),
      ),
    );
  }

  // ── Main dropdown items ────────────────────────────────────────────────────
  Widget _buildMainDropdownItems() {
    return Column(
      key: const ValueKey('main'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Lock screen
        _dropItem(
          icon: Icons.lock_rounded,
          label: 'Lock Screen',
          onTap: () {
            setState(() {
              _showDropdown = false;
              _showControls = false;
              _isLocked = true;
            });
            _hideControlsTimer?.cancel();
            _showLockBadgeTemporarily();
          },
        ),
        _divider(),
        // Fill / fit
        _dropItem(
          icon: _isExpanded ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          label: _isExpanded ? 'Fit to Screen' : 'Fill Screen',
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
              _showDropdown = false;
            });
            _resetHideControlsTimer();
          },
        ),
        // Pending requests — host only
        if (widget.isOwner) ...[
          _divider(),
          _dropItem(
            icon: Icons.person_add_rounded,
            label: 'Pending Requests',
            badge: _pendingRequests.length,
            onTap: () {
              setState(() => _showPendingRequests = true);
              _hideControlsTimer?.cancel();
            },
          ),
        ],
      ],
    );
  }

  // ── Pending requests panel ─────────────────────────────────────────────────
  // iPhone 8 stacked notification card style
  // Cards stack on each other, scroll reveals next, accept/reject fades card away
  Widget _buildPendingRequestsPanel() {
    return Column(
      key: const ValueKey('pending'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header with back button
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _showPendingRequests = false),
                child: Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white.withOpacity(0.6), size: 14),
              ),
              const SizedBox(width: 8),
              Text(
                'PENDING REQUESTS',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.white.withOpacity(0.50),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Text(
                '${_pendingRequests.length}',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.niorRed,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        _divider(),

        if (_pendingRequests.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'No pending requests',
              style: TextStyle(
                fontFamily: 'Inter',
                color: Colors.white.withOpacity(0.25),
                fontSize: 12,
              ),
            ),
          )
        else
          // Stacked scrollable cards — iPhone 8 notification style
          SizedBox(
            height: _pendingRequests.length == 1 ? 72 : 120,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              itemCount: _pendingRequests.length,
              itemBuilder: (context, index) {
                final req = _pendingRequests[index];
                return _buildRequestCard(req, index);
              },
            ),
          ),
      ],
    );
  }

  // ── Individual request card ────────────────────────────────────────────────
  Widget _buildRequestCard(PendingJoinRequest req, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.10), width: 0.8),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            // Avatar
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.darkGray,
                border: Border.all(color: Colors.white.withOpacity(0.15), width: 0.8),
              ),
              child: ClipOval(
                child: req.avatarPath != null
                    ? Image.file(File(req.avatarPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _reqInitial(req))
                    : _reqInitial(req),
              ),
            ),
            const SizedBox(width: 10),
            // Username
            Expanded(
              child: Text(
                req.username,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Reject button — red X
            GestureDetector(
              onTap: () => _rejectRequest(req),
              child: Container(
                width: 32, height: 32,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.error.withOpacity(0.15),
                  border: Border.all(
                      color: AppColors.error.withOpacity(0.40), width: 0.8),
                ),
                child: Icon(Icons.close_rounded,
                    color: AppColors.error, size: 16),
              ),
            ),
            // Accept button — green tick
            GestureDetector(
              onTap: () => _acceptRequest(req),
              child: Container(
                width: 32, height: 32,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.success.withOpacity(0.15),
                  border: Border.all(
                      color: AppColors.success.withOpacity(0.40), width: 0.8),
                ),
                child: Icon(Icons.check_rounded,
                    color: AppColors.success, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reqInitial(PendingJoinRequest req) {
    return Container(
      color: AppColors.darkGray,
      child: Center(
        child: Text(
          req.username.isNotEmpty ? req.username[0].toUpperCase() : '?',
          style: const TextStyle(
              fontFamily: 'BebasNeue', color: Colors.white, fontSize: 14),
        ),
      ),
    );
  }

  Widget _dropItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 17),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.niorRed,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge.toString(),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Divider(
      height: 1, thickness: 0.5, color: Colors.white.withOpacity(0.08));

  // ── Lock overlay ───────────────────────────────────────────────────────────
  Widget _buildLockOverlay() {
    return Positioned(
      top: 20, right: 16,
      child: AnimatedOpacity(
        opacity: _showLockBadge ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: GestureDetector(
          onTap: () {
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
              color: Colors.black.withOpacity(0.65),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.25), width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text('Tap to unlock',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.white,
                        fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Avatar panel ───────────────────────────────────────────────────────────
  Widget _buildAvatarPanel() {
    return Positioned(
      right: 12, bottom: 80,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: _participants.map(_buildAvatarBubble).toList(),
      ),
    );
  }

  Widget _buildAvatarBubble(RoomParticipant p) {
    final ctrl = _speakControllers[p.userId];
    final isSelf = p.userId == widget.currentUser.userId;

    return GestureDetector(
      onLongPress: widget.isOwner && !isSelf
          ? () => _showParticipantMenu(p)
          : null,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (p.isSpeaking && ctrl != null)
              AnimatedBuilder(
                animation: ctrl,
                builder: (_, __) => Container(
                  width: 52 + (ctrl.value * 12),
                  height: 52 + (ctrl.value * 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.niorRed.withOpacity(0.6 - ctrl.value * 0.4),
                      width: 2,
                    ),
                  ),
                ),
              ),
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: p.isOwner
                      ? AppColors.niorRed
                      : isSelf
                          ? Colors.white.withOpacity(0.5)
                          : Colors.white.withOpacity(0.15),
                  width: p.isOwner ? 2 : 1,
                ),
                color: AppColors.darkGray,
              ),
              child: ClipOval(
                child: p.avatarPath != null
                    ? Image.file(File(p.avatarPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _defaultAvatar(p))
                    : _defaultAvatar(p),
              ),
            ),
            if (p.isOwner)
              Positioned(
                top: -2, right: -2,
                child: Container(
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: AppColors.accentGold),
                  child: const Icon(Icons.star_rounded, color: Colors.black, size: 10),
                ),
              ),
            if (p.isMuted)
              Positioned(
                bottom: -2, right: -2,
                child: Container(
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: AppColors.error),
                  child: const Icon(Icons.mic_off_rounded, color: Colors.white, size: 9),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _defaultAvatar(RoomParticipant p) {
    return Container(
      color: AppColors.darkGray,
      child: Center(
        child: Text(
          p.username.isNotEmpty ? p.username[0].toUpperCase() : '?',
          style: const TextStyle(
              fontFamily: 'BebasNeue', color: Colors.white, fontSize: 18),
        ),
      ),
    );
  }

  Widget _buildAvatarToggle() {
    return Positioned(
      top: 16, right: 16,
      child: GestureDetector(
        onTap: () => setState(() => _showAvatars = !_showAvatars),
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withOpacity(0.45),
            border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8),
          ),
          child: Icon(
            _showAvatars ? Icons.people_rounded : Icons.people_outline_rounded,
            color: Colors.white.withOpacity(0.6), size: 16,
          ),
        ),
      ),
    );
  }

  Widget _participantBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_rounded, color: Colors.white.withOpacity(0.6), size: 12),
          const SizedBox(width: 5),
          Text('${_participants.length}',
              style: TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showParticipantMenu(RoomParticipant p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.80),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08), width: 0.8)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text('@${p.username}',
                    style: const TextStyle(
                        fontFamily: 'BebasNeue', color: Colors.white,
                        fontSize: 18, letterSpacing: 1)),
                const SizedBox(height: 20),
                _menuItem(
                  icon: p.isMuted ? Icons.mic_rounded : Icons.mic_off_rounded,
                  label: p.isMuted ? 'Unmute' : 'Mute',
                  color: Colors.white,
                  onTap: () { Navigator.pop(context); _muteParticipant(p.userId); },
                ),
                const SizedBox(height: 10),
                _menuItem(
                  icon: Icons.exit_to_app_rounded,
                  label: 'Remove from room',
                  color: AppColors.error,
                  onTap: () {
                    Navigator.pop(context);
                    _watchService?.sendKick(p.userId);
                    setState(() => _participants.removeWhere((e) => e.userId == p.userId));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.15), width: 0.8),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(fontFamily: 'Inter', color: color,
                    fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  void _confirmLeave() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(widget.isOwner ? 'End Room?' : 'Leave Room?',
            style: const TextStyle(fontFamily: 'BebasNeue', color: Colors.white,
                fontSize: 20, letterSpacing: 1)),
        content: Text(
          widget.isOwner
              ? 'Ending the room will disconnect all participants.'
              : 'You can rejoin using the room link.',
          style: TextStyle(fontFamily: 'Inter',
              color: Colors.white.withOpacity(0.40), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Stay', style: TextStyle(fontFamily: 'Inter',
                color: Colors.white.withOpacity(0.35))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (widget.isOwner) _stopRoom();
              else Navigator.pop(context);
            },
            child: Text(widget.isOwner ? 'End' : 'Leave',
                style: TextStyle(fontFamily: 'Inter', color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _showKickedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Removed from room',
            style: TextStyle(fontFamily: 'BebasNeue', color: Colors.white,
                fontSize: 20, letterSpacing: 1)),
        content: Text('The host has removed you from this room.',
            style: TextStyle(fontFamily: 'Inter',
                color: Colors.white.withOpacity(0.40), fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); Navigator.pop(context); },
            child: const Text('OK',
                style: TextStyle(fontFamily: 'Inter', color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRoomEndedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Room ended',
            style: TextStyle(fontFamily: 'BebasNeue', color: Colors.white,
                fontSize: 20, letterSpacing: 1)),
        content: Text('The host has ended the room.',
            style: TextStyle(fontFamily: 'Inter',
                color: Colors.white.withOpacity(0.40), fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); Navigator.pop(context); },
            child: const Text('OK',
                style: TextStyle(fontFamily: 'Inter', color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() => Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.niorRed)),
              const SizedBox(height: 14),
              Text('Loading video...',
                  style: TextStyle(fontFamily: 'Inter',
                      color: Colors.white.withOpacity(0.30), fontSize: 13)),
            ],
          ),
        ),
      );

  Widget _buildConnectingBadge() => Positioned(
        bottom: 20, left: 0, right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 10, height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.2, color: AppColors.niorRed)),
                const SizedBox(width: 8),
                Text('Connecting to room...',
                    style: TextStyle(fontFamily: 'Inter',
                        color: Colors.white.withOpacity(0.35), fontSize: 11)),
              ],
            ),
          ),
        ),
      );

  Widget _buildErrorOverlay() => Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(_videoErrorMessage,
                    style: TextStyle(fontFamily: 'Inter',
                        color: Colors.white.withOpacity(0.50), fontSize: 13),
                    textAlign: TextAlign.center),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8),
                  ),
                  child: const Text('Leave',
                      style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _glassBtn({required IconData icon, required VoidCallback onTap, Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.10),
              border: Border.all(color: Colors.white.withOpacity(0.15), width: 0.8),
            ),
            child: Icon(icon, color: color ?? Colors.white, size: 17),
          ),
        ),
      ),
    );
  }

  Widget _centerBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.10),
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}