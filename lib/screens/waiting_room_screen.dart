import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noirscreen/services/rooms_service.dart';
import 'package:noirscreen/services/room_watch_service.dart';
import 'package:noirscreen/services/webrtc_service.dart';
import '../constants/app_colors.dart';
import '../models/scheduled_room_model.dart';
import '../models/user_model.dart';
import '../providers/rooms_provider.dart';
import '../services/api_services.dart';
import 'room_watch_screen.dart';

class WaitingRoomScreen extends ConsumerStatefulWidget {
  final ScheduledRoomModel room;
  final UserModel currentUser;
  final bool isOwner;

  const WaitingRoomScreen({
    super.key,
    required this.room,
    required this.currentUser,
    required this.isOwner,
  });

  @override
  ConsumerState<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends ConsumerState<WaitingRoomScreen>
    with TickerProviderStateMixin {

  // ── Countdown ──────────────────────────────────────────────────────────────
  Duration _timeUntil = Duration.zero;
  Timer? _countdownTimer;

  // ── Thumbnail expand animation ─────────────────────────────────────────────
  bool _isExpanding = false;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  // ── Poll backend ───────────────────────────────────────────────────────────
  Timer? _pollTimer;
  bool _navigating = false;

  // ── Participants ───────────────────────────────────────────────────────────
  final List<_WaitingParticipant> _participants = [];
  bool _isMuted = false;

  // ── Host start ─────────────────────────────────────────────────────────────
  bool _isStarting = false;
  final RoomsService _roomsService = RoomsService();

  // ── Landscape animation controller ────────────────────────────────────────
  late AnimationController _landscapeController;
  late Animation<double> _landscapeAnimation;

  // ── Socket + WebRTC for voice in waiting room ──────────────────────────────
  RoomWatchService? _watchService;
  WebRTCService? _webrtc;

  // ── Reactions ─────────────────────────────────────────────────────────────
  final List<_WaitingReaction> _activeReactions = [];

  static const List<String> _reactionEmojis = [
    'assets/reactions/react_heart.png',
    'assets/reactions/react_laugh.png',
    'assets/reactions/react_shocked.png',
    'assets/reactions/react_fire.png',
    'assets/reactions/react_clap.png',
    'assets/reactions/react_cry.png',
    'assets/reactions/react_starstruck.png',
    'assets/reactions/react_skull.png',
    'assets/reactions/react_eyes.png',
    'assets/reactions/react_popcorn.png',
  ];

  bool _showReactions = false;

  @override
  void initState() {
    super.initState();

    // Landscape mode — matches video player
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _participants.add(_WaitingParticipant(
      userId: widget.currentUser.userId,
      username: widget.currentUser.username,
      isOwner: widget.isOwner,
      isMuted: false,
      avatarUrl: widget.currentUser.photoUrl,
    ));

    _expandController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOutCubic,
    );

    _landscapeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _landscapeAnimation = CurvedAnimation(
      parent: _landscapeController,
      curve: Curves.easeInOutCubic,
    );

    _startCountdown();
    _startPolling();
    _initVoice();
  }

  // ── Init voice chat in waiting room ────────────────────────────────────────
  Future<void> _initVoice() async {
    try {
      final service = RoomWatchService(
        roomId: widget.room.roomId,
        userId: widget.currentUser.userId,
        isOwner: widget.isOwner,
      );

      await service.connect(
        onPlay: (_) {},
        onPause: (_) {},
        onSeek: (_) {},
        onParticipantJoined: (uid, uname, avatar) {
          if (!mounted) return;
          final exists = _participants.any((p) => p.userId == uid);
          if (!exists) {
            setState(() => _participants.add(_WaitingParticipant(
              userId: uid, username: uname,
              isOwner: false, isMuted: false, avatarUrl: avatar,
            )));
          }
          // Delay offer until WebRTC is guaranteed initialized
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _webrtc?.createOffer(uid);
          });
        },
        onParticipantLeft: (uid) {
          if (!mounted) return;
          setState(() => _participants.removeWhere((p) => p.userId == uid));
          _webrtc?.removePeer(uid);
        },
        onSpeaking: (uid, speaking) {
          if (!mounted) return;
          setState(() {
            final idx = _participants.indexWhere((p) => p.userId == uid);
            if (idx != -1) _participants[idx].isSpeaking = speaking;
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
            Navigator.pop(context);
          }
        },
        onRoomEnded: () {
          if (mounted) Navigator.pop(context);
        },
        onWebRTCOffer: (fromUserId, sdp) async {
          await _webrtc?.handleOffer(fromUserId, sdp);
        },
        onWebRTCAnswer: (fromUserId, sdp) async {
          await _webrtc?.handleAnswer(fromUserId, sdp);
        },
        onWebRTCIce: (fromUserId, candidate) async {
          await _webrtc?.handleIceCandidate(fromUserId, candidate);
        },
        onReaction: (uid, emoji) {
          if (!mounted) return;
          _addReactionBubble(uid, emoji);
        },
      );
      if (mounted) {
  // Initialize WebRTC FIRST — same fix as watch screen
  // Prevents null _webrtc when participant_joined fires early
  _webrtc = WebRTCService(
    localUserId: widget.currentUser.userId,
    watchService: service,
    onSpeakingChanged: (uid, speaking) {
      if (!mounted) return;
      setState(() {
        final idx = _participants.indexWhere((p) => p.userId == uid);
        if (idx != -1) _participants[idx].isSpeaking = speaking;
      });
    },
    onPeerDisconnected: (uid) => print('📡 WEBRTC WAIT: $uid disconnected'),
  );
  await _webrtc!.initialize();

  // Set service only after webrtc is ready
  setState(() => _watchService = service);
}

    } catch (e) {
      print('❌ WAITING ROOM: voice init error - $e');
    }
  }

  void _addReactionBubble(String userId, String emoji) {
    final id = '${userId}_${DateTime.now().millisecondsSinceEpoch}';
    final ctrl = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );
    final fadeAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: ctrl, curve: const Interval(0.6, 1.0, curve: Curves.easeOut)),
    );
    final slideAnim = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -1.5),
    ).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeOut));

    final username = _participants
        .firstWhere((p) => p.userId == userId, orElse: () => _WaitingParticipant(userId: userId, username: 'User', isOwner: false, isMuted: false))
        .username;

    final bubble = _WaitingReaction(
      userId: userId, username: username, emoji: emoji,
      id: id, controller: ctrl, fadeAnim: fadeAnim, slideAnim: slideAnim,
    );

    setState(() => _activeReactions.add(bubble));
    ctrl.forward().then((_) {
      if (mounted) {
        setState(() => _activeReactions.removeWhere((r) => r.id == id));
        ctrl.dispose();
      }
    });
  }

  void _sendReaction(String emojiPath) {
  if (_watchService == null) {
    print('⚠️ REACTION: service not ready, skipping');
    return;
  }
  // Server echoes back to all including sender — no local add needed
  _watchService!.sendReaction(emojiPath);
}

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _webrtc?.setMuted(_isMuted);
  }

  // ── Countdown ──────────────────────────────────────────────────────────────
  void _startCountdown() {
    _updateTimeUntil();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTimeUntil());
  }

  void _updateTimeUntil() {
    if (!mounted) return;
    final now = DateTime.now();
    final diff = widget.room.scheduledAt.difference(now);
    setState(() => _timeUntil = diff.isNegative ? Duration.zero : diff);

    if (diff.isNegative && !_isExpanding) {
      setState(() => _isExpanding = true);
      _expandController.forward().then((_) async {
        if (!mounted || _navigating) return;
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted && !_navigating) _checkAndNavigate();
      });
    }
  }

void _startPolling() {
    // Poll every 10s for viewer, 15s for host
    // Viewer uses direct API call — not provider (provider only has host's rooms)
    _pollTimer = Timer.periodic(
      Duration(seconds: widget.isOwner ? 15 : 10),
      (_) { if (mounted) _checkAndNavigate(); },
    );
  }

  Future<void> _checkAndNavigate() async {
    if (_navigating || !mounted) return;

    if (widget.isOwner) {
      // Host: use provider (their rooms are in there)
      ref.invalidate(scheduledRoomsProvider);
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || _navigating) return;
      final asyncVal = ref.read(scheduledRoomsProvider);
      final rooms = asyncVal.when(data: (r) => r, loading: () => null, error: (_, __) => null);
      if (rooms == null) return;
      final updated = rooms.where((r) => r.roomId == widget.room.roomId);
      if (updated.isEmpty) return;
      final room = updated.first;
      if (room.status == 'active') _navigateToWatch(room);
    } else {
      // Viewer: hit backend directly — provider only has host's rooms
      final room = await _roomsService.getRoomById(widget.room.roomId);
      if (!mounted || _navigating || room == null) return;
      if (room.status == 'active') _navigateToWatch(room);
    }
  }

  Future<void> _navigateToWatch(ScheduledRoomModel room) async {
    if (_navigating || !mounted) return;
    _navigating = true;
    _countdownTimer?.cancel();
    _pollTimer?.cancel();

    // Disconnect voice before handing off to watch screen
    // Watch screen will re-init its own socket + WebRTC
    _watchService?.disconnect();
    await _webrtc?.dispose();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => RoomWatchScreen(
          room: room,
          currentUser: widget.currentUser,
          isOwner: widget.isOwner,
          localFilePath: widget.isOwner ? room.videoFilePath : null,
          hlsStreamUrl: widget.isOwner
              ? null
              : '${ApiService.baseUrl}/api/rooms/${room.roomId}/stream.m3u8',
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeIn),
          child: child,
        ),
      ),
    );
  }

  Future<void> _hostStartNow() async {
    if (_isStarting || !mounted) return;
    setState(() => _isStarting = true);

    try {
      final success = await _roomsService.startRoom(widget.room.roomId);
      if (!mounted) return;

      if (success) {
        setState(() => _isExpanding = true);
        await _expandController.forward();
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted || _navigating) return;
        _navigateToWatch(widget.room.copyWith(status: 'active'));
      } else {
        if (mounted) setState(() => _isStarting = false);
      }
    } catch (e) {
      print('❌ WAITING ROOM: startRoom error - $e');
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    _expandController.dispose();
    _landscapeController.dispose();
    _watchService?.disconnect();
    _webrtc?.dispose();
    for (final r in _activeReactions) r.controller.dispose();
    if (!_navigating) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    }
    super.dispose();
  }

  String _fmtCountdown(Duration d) {
    if (d == Duration.zero) return '00:00';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Thumbnail ──────────────────────────────────────────────────────
            AnimatedBuilder(
            animation: _expandAnimation,
            builder: (context, child) {
              final hPad = (1 - _expandAnimation.value) * size.width * 0.18;
              final vPad = (1 - _expandAnimation.value) * size.height * 0.14;
              return Positioned(left: hPad, right: hPad, top: vPad, bottom: vPad, child: child!);
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_isExpanding ? 0 : 14),
              child: widget.room.videoThumbnailPath != null &&
                      File(widget.room.videoThumbnailPath!).existsSync()
                  ? Image.file(
                      File(widget.room.videoThumbnailPath!),
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    )
                  : Container(
                      color: AppColors.darkGray,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.movie_rounded, color: Colors.white.withOpacity(0.15), size: 64),
                        const SizedBox(height: 12),
                        Text(widget.room.videoTitle,
                          style: const TextStyle(fontFamily: 'BebasNeue', color: Colors.white, fontSize: 20, letterSpacing: 1),
                          textAlign: TextAlign.center),
                      ]),
                    ),
            ),
          ),
          // ── Gradient overlay ───────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.50), Colors.transparent, Colors.black.withOpacity(0.60), Colors.black.withOpacity(0.95)],
                stops: const [0.0, 0.35, 0.62, 1.0],
              ),
            ),
          ),

          // ── Floating reaction bubbles ──────────────────────────────────────
          ..._activeReactions.map((r) => _buildReactionBubble(r)),

          // ── Main UI ────────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _confirmLeave,
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.08), border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8)),
                          child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 17),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(widget.room.videoTitle, style: const TextStyle(fontFamily: 'BebasNeue', color: Colors.white, fontSize: 20, letterSpacing: 1), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('Hosted by ${widget.isOwner ? "you" : "host"}', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withOpacity(0.35), fontSize: 11)),
                        ]),
                      ),
                      // Participant count
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.people_rounded, color: Colors.white.withOpacity(0.5), size: 12),
                          const SizedBox(width: 5),
                          Text('${_participants.length}', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Countdown or Starting
                Center(
                  child: !_isExpanding
                      ? Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: AppColors.accentGold.withOpacity(0.12), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.accentGold.withOpacity(0.3), width: 0.6)),
                            child: Text('STARTING IN', style: TextStyle(fontFamily: 'Inter', color: AppColors.accentGold, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 2)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _fmtCountdown(_timeUntil),
                            style: TextStyle(
                              fontFamily: 'BebasNeue', color: Colors.white, fontSize: 64, letterSpacing: 4,
                              shadows: [Shadow(color: AppColors.niorRed.withOpacity(0.3), blurRadius: 20)],
                            ),
                          ),
                        ])
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.niorRed)),
                          const SizedBox(width: 10),
                          Text('Starting...', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withOpacity(0.60), fontSize: 14)),
                        ]),
                ),

                const SizedBox(height: 16),

                // Reaction bar — shows when _showReactions toggled
                if (_showReactions)
                  SizedBox(
                    height: 52,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _reactionEmojis.length,
                      itemBuilder: (context, i) => GestureDetector(
                        onTap: () { _sendReaction(_reactionEmojis[i]); setState(() => _showReactions = false); },
                        child: Container(
                          width: 44, height: 44,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.45), border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8)),
                          padding: const EdgeInsets.all(6),
                          child: Image.asset(_reactionEmojis[i], fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.emoji_emotions_rounded, color: Colors.white, size: 20)),
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 8),

                // Bottom bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Avatar bubbles — scrollable
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _participants.length,
                            itemBuilder: (ctx, i) => _buildParticipantBubble(_participants[i]),
                          ),
                        ),
                      ),

                      // Reaction toggle
                      _controlBtn(
                        icon: Icons.emoji_emotions_rounded,
                        label: 'React',
                        color: _showReactions ? AppColors.accentGold : Colors.white.withOpacity(0.7),
                        onTap: () => setState(() => _showReactions = !_showReactions),
                      ),

                      const SizedBox(width: 12),

                      // Mute toggle
                      _controlBtn(
                        icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        label: _isMuted ? 'Unmute' : 'Mute',
                        color: _isMuted ? AppColors.error : Colors.white.withOpacity(0.7),
                        onTap: _toggleMute,
                      ),

                      // Host START NOW button
                      if (widget.isOwner) ...[
                        const SizedBox(width: 14),
                        GestureDetector(
                          onTap: _isStarting ? null : _hostStartNow,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                            decoration: BoxDecoration(color: AppColors.niorRed, borderRadius: BorderRadius.circular(12)),
                            child: _isStarting
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                                : Row(mainAxisSize: MainAxisSize.min, children: const [
                                    Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                                    SizedBox(width: 6),
                                    Text('START NOW', style: TextStyle(fontFamily: 'BebasNeue', color: Colors.white, fontSize: 16, letterSpacing: 1)),
                                  ]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionBubble(_WaitingReaction r) {
    final participant = _participants.firstWhere(
      (p) => p.userId == r.userId,
      orElse: () => _WaitingParticipant(userId: r.userId, username: r.username, isOwner: false, isMuted: false),
    );
    final double rightOffset = 60.0 + (r.id.hashCode.abs() % 180).toDouble();
    return Positioned(
      right: rightOffset, bottom: 100,
      child: FadeTransition(
        opacity: r.fadeAnim,
        child: SlideTransition(
          position: r.slideAnim,
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.darkGray, border: Border.all(color: AppColors.niorRed.withOpacity(0.5), width: 1.5)),
              child: ClipOval(child: _avatarWidget(participant)),
            ),
            const SizedBox(width: 6),
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.55), border: Border.all(color: Colors.white.withOpacity(0.15), width: 0.8)),
              padding: const EdgeInsets.all(6),
              child: Image.asset(r.emoji, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.emoji_emotions_rounded, color: Colors.white, size: 24)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildParticipantBubble(_WaitingParticipant p) {
    final isSelf = p.userId == widget.currentUser.userId;
    final borderColor = p.isOwner ? AppColors.niorRed : isSelf ? Colors.white.withOpacity(0.5) : Colors.white.withOpacity(0.15);

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // Speaking ring
              if (p.isSpeaking)
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.niorRed.withOpacity(0.6), width: 2)),
                ),
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.darkGray, border: Border.all(color: borderColor, width: p.isOwner ? 2 : 1)),
                child: ClipOval(child: _avatarWidget(p)),
              ),
              if (p.isOwner)
                Positioned(top: -2, right: -2, child: Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accentGold), child: const Icon(Icons.star_rounded, color: Colors.black, size: 9))),
            ],
          ),
          if (p.isMuted) ...[
            const SizedBox(height: 2),
            Icon(Icons.mic_off_rounded, color: AppColors.error, size: 10),
          ],
        ],
      ),
    );
  }

  Widget _avatarWidget(_WaitingParticipant p) {
    final url = p.avatarUrl;
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('data:image')) {
        try {
          final base64Part = url.contains(',') ? url.split(',').last : url;
          final cleaned = base64Part.replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '');
          final rem = cleaned.length % 4;
          final normalised = rem == 0 ? cleaned : cleaned + '=' * (4 - rem);
          final bytes = base64Decode(normalised);
          return Image.memory(bytes, width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _initialsWidget(p.username));
        } catch (_) { return _initialsWidget(p.username); }
      }
      if (url.startsWith('/')) return Image.file(File(url), width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _initialsWidget(p.username));
      if (url.startsWith('http')) return Image.network(url, width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _initialsWidget(p.username));
    }
    return _initialsWidget(p.username);
  }

  Widget _initialsWidget(String username) => Center(
    child: Text(username.isNotEmpty ? username[0].toUpperCase() : '?', style: const TextStyle(fontFamily: 'BebasNeue', color: Colors.white, fontSize: 16)),
  );

  Widget _controlBtn({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.08), border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontFamily: 'Inter', color: Colors.white.withOpacity(0.40), fontSize: 9)),
      ]),
    );
  }

  void _confirmLeave() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(widget.isOwner ? 'Cancel Room?' : 'Leave Waiting Room?', style: const TextStyle(fontFamily: 'BebasNeue', color: Colors.white, fontSize: 20, letterSpacing: 1)),
        content: Text(widget.isOwner ? 'This will cancel the room for everyone.' : 'You can rejoin using the room link.', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withOpacity(0.40), fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Stay', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withOpacity(0.35)))),
          TextButton(
            onPressed: () { Navigator.pop(context); Navigator.pop(context); },
            child: Text(widget.isOwner ? 'Cancel Room' : 'Leave', style: TextStyle(fontFamily: 'Inter', color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

// ── Participant model ──────────────────────────────────────────────────────────
class _WaitingParticipant {
  final String userId;
  final String username;
  final bool isOwner;
  bool isMuted;
  bool isSpeaking;
  final String? avatarUrl;

  _WaitingParticipant({
    required this.userId,
    required this.username,
    required this.isOwner,
    required this.isMuted,
    this.isSpeaking = false,
    this.avatarUrl,
  });
}

// ── Reaction bubble model ──────────────────────────────────────────────────────
class _WaitingReaction {
  final String userId;
  final String username;
  final String emoji;
  final String id;
  final AnimationController controller;
  final Animation<double> fadeAnim;
  final Animation<Offset> slideAnim;

  _WaitingReaction({
    required this.userId,
    required this.username,
    required this.emoji,
    required this.id,
    required this.controller,
    required this.fadeAnim,
    required this.slideAnim,
  });
}