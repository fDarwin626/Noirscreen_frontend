import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noirscreen/screens/waiting_room_screen.dart';
import 'package:noirscreen/services/rooms_service.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_style.dart';
import '../models/scheduled_room_model.dart';
import '../models/user_model.dart';
import '../providers/rooms_provider.dart';
import '../services/auth_service.dart';
import '../services/api_services.dart';
import 'room_video_picker_screen.dart';
import 'room_watch_screen.dart';

class RoomsScreen extends ConsumerStatefulWidget {
  const RoomsScreen({super.key});

  @override
  ConsumerState<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends ConsumerState<RoomsScreen>
    with TickerProviderStateMixin {
  ScheduledRoomModel? _lastCompletedRoom;
  UserModel? _currentUser;
  bool _loadingUser = true;
  final RoomsService _roomsService = RoomsService();
  Timer? _refreshTimer;
  final TextEditingController _joinLinkController = TextEditingController();
  bool _isJoining = false;

  AnimationController? _entryController;
  Animation<double>? _entryFade;
  Animation<Offset>? _entrySlide;

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      duration: const Duration(milliseconds: 480),
      vsync: this,
    );
    _entryFade =
        CurvedAnimation(parent: _entryController!, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _entryController!, curve: Curves.easeOutCubic));

    _loadCurrentUser();
    _loadLastCompletedRoom();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.invalidate(scheduledRoomsProvider);
        _entryController?.forward();
      }
    });

    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) ref.invalidate(scheduledRoomsProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _joinLinkController.dispose();
    _entryController?.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final authService = AuthService();
      final apiService = ApiService();
      final userId = await authService.getUserId();
      if (userId == null) {
        if (mounted) setState(() => _loadingUser = false);
        return;
      }
      final user = await apiService.getUser(userId);
      if (mounted) {
        setState(() {
          _currentUser = user;
          _loadingUser = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingUser = false);
    }
  }

  Future<void> _loadLastCompletedRoom() async {
    try {
      final rooms = await _roomsService.getCompletedRooms();
      if (rooms.isNotEmpty && mounted) {
        setState(() => _lastCompletedRoom = rooms.first);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheduledRooms = ref.watch(scheduledRoomsProvider);

    final content = CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildHeader()),
        SliverToBoxAdapter(
          child: scheduledRooms.when(
            data: (rooms) => rooms.isEmpty
                ? const SizedBox.shrink()
                : _buildScheduledSection(rooms),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ),
        SliverToBoxAdapter(child: _buildStartRoom()),
        SliverToBoxAdapter(child: _buildBottomSection()),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: _entryFade == null
            ? content
            : FadeTransition(
                opacity: _entryFade!,
                child: SlideTransition(
                  position: _entrySlide!,
                  child: content,
                ),
              ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ROOMS',
            style: AppTextStyles.header2.copyWith(
              color: AppColors.textWhite,
              fontSize: 28,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Watch together. Anywhere. In sync.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.ashGray,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),
          _buildJoinField(),
        ],
      ),
    );
  }

  // ── Join field ──────────────────────────────────────────────────────────────
  Widget _buildJoinField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.charcoal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded,
              color: AppColors.ashGray.withOpacity(0.45), size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _joinLinkController,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textWhite,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Paste room link to join...',
                hintStyle: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.ashGray.withOpacity(0.35),
                  fontSize: 13,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => _joinViaLink(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isJoining ? null : _joinViaLink,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _isJoining
                    ? Colors.white.withOpacity(0.04)
                    : AppColors.niorRed,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _isJoining
                  ? SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    )
                  : Text(
                      'JOIN',
                      style: AppTextStyles.button.copyWith(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _joinViaLink() async {
    final link = _joinLinkController.text.trim();
    if (link.isEmpty) return;
    if (!link.startsWith('noirscreen://room/')) {
      _showSnack('Invalid room link format', isError: true);
      return;
    }
    setState(() => _isJoining = true);
    try {
      final room = await _roomsService.joinViaLink(link);
      if (room == null || !mounted || _currentUser == null) return;
      _joinLinkController.clear();
      _navigateToRoom(room, isOwner: false);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceAll('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        msg,
        style: AppTextStyles.bodySmall.copyWith(
          color: Colors.white,
          fontSize: 13,
        ),
      ),
      backgroundColor: isError ? AppColors.error : AppColors.charcoal,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
  }

  void _navigateToRoom(ScheduledRoomModel room, {required bool isOwner}) {
    if (_currentUser == null) return;
    if (room.status != 'active') {
      Navigator.push(context, _pageRoute(WaitingRoomScreen(
        room: room,
        currentUser: _currentUser!,
        isOwner: isOwner,
      )));
      return;
    }
    Navigator.push(context, _pageRoute(RoomWatchScreen(
      room: room,
      currentUser: _currentUser!,
      isOwner: isOwner,
      localFilePath: isOwner ? room.videoFilePath : null,
      hlsStreamUrl: isOwner
          ? null
          : '${ApiService.baseUrl}/api/rooms/${room.roomId}/stream.m3u8',
    )));
  }

  // ── Scheduled section ───────────────────────────────────────────────────────
  Widget _buildScheduledSection(List<ScheduledRoomModel> rooms) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Text(
            'SCHEDULED',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.ashGray,
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const BouncingScrollPhysics(),
            itemCount: rooms.length,
            itemBuilder: (_, i) => _ScheduledRoomCard(
              room: rooms[i],
              currentUser: _currentUser,
              onCancel: () => _showCancelDialog(rooms[i]),
              onTap: () {
                if (_currentUser == null) return;
                _navigateToRoom(rooms[i],
                    isOwner: rooms[i].hostId == _currentUser!.userId);
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  void _showCancelDialog(ScheduledRoomModel room) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.charcoal,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Cancel Room?',
          style: AppTextStyles.bodyBold.copyWith(
            color: AppColors.textWhite,
            fontSize: 17,
          ),
        ),
        content: Text(
          'This will cancel "${room.videoTitle}" for everyone.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.ashGray.withOpacity(0.6),
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(children: [
            Expanded(
              child: _FlatButton(
                label: 'Keep It',
                onTap: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _FlatButton(
                label: 'Cancel Room',
                isDestructive: true,
                onTap: () async {
                  Navigator.pop(context);
                  final ok = await _roomsService.cancelRoom(room.roomId);
                  if (ok && mounted) ref.invalidate(scheduledRoomsProvider);
                },
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ── Start a Room ────────────────────────────────────────────────────────────
  Widget _buildStartRoom() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'START A ROOM',
            style: AppTextStyles.caption.copyWith(
              color: const Color(0xFF555555),
              fontSize: 10,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          _WatchWithFriendCard(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                _pageRoute(
                    const RoomVideoPickerScreen(streamType: 'audio')),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Bottom section ──────────────────────────────────────────────────────────
  Widget _buildBottomSection() {
    if (_lastCompletedRoom != null) {
      return _buildLastStreamedCard(_lastCompletedRoom!);
    }
    return Container(
      height: 180,
      margin: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      decoration: BoxDecoration(
        color: AppColors.charcoal,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
          width: 1,
        ),
      ),
      child: Center(
        child: Image.asset(
          'assets/images/streamer.png',
          width: 160,
          errorBuilder: (_, __, ___) => Icon(
            Icons.movie_outlined,
            color: AppColors.ashGray.withOpacity(0.12),
            size: 48,
          ),
        ),
      ),
    );
  }

  Widget _buildLastStreamedCard(ScheduledRoomModel room) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.charcoal,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: room.videoThumbnailPath != null
                ? Image.file(
                    File(room.videoThumbnailPath!),
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _thumbFallback(),
                  )
                : _thumbFallback(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LAST STREAMED',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.ashGray.withOpacity(0.4),
                    fontSize: 9,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  room.videoTitle,
                  style: AppTextStyles.bodyBold.copyWith(
                    color: AppColors.textWhite,
                    fontSize: 14,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  _streamTypeLabel(room.streamType),
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.ashGray.withOpacity(0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.08),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: AppColors.success.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Text(
              'DONE',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.success,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbFallback() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.movie_outlined,
          color: AppColors.ashGray.withOpacity(0.25), size: 20),
    );
  }

  String _streamTypeLabel(String type) {
    switch (type) {
      case 'sync':  return 'Sync Watch';
      case 'hls':   return 'Video Stream';
      case 'audio': return 'Audio Stream';
      default:      return 'Stream';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Watch With a Friend card — matches original grid card aesthetic
// ─────────────────────────────────────────────────────────────────────────────
class _WatchWithFriendCard extends StatelessWidget {
  final VoidCallback onTap;

  const _WatchWithFriendCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF131313),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF1E1E1E),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left column — icon, label, divider, subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.mic_none_rounded,
                    color: AppColors.textWhite,
                    size: 26,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Watch With\na Friend',
                    style: AppTextStyles.bodyBold.copyWith(
                      color: const Color(0xFFE8E8E8),
                      fontSize: 15,
                      height: 1.25,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(
                      height: 1,
                      thickness: 0.6,
                      color: Color(0xFF1E1E1E),
                    ),
                  ),
                  Text(
                    'VOICE + SYNC',
                    style: AppTextStyles.caption.copyWith(
                      color: const Color(0xFF3A3A3A),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            // Right column — description + start button
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 46),
                  Text(
                    'Pick a video from your phone. Share the link. Watch in perfect sync.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.ashGray.withOpacity(0.45),
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.niorRed.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: AppColors.niorRed.withOpacity(0.22),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Start',
                            style: AppTextStyles.button.copyWith(
                              color: AppColors.niorRed,
                              fontSize: 12,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: AppColors.niorRed,
                            size: 13,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Flat dialog button
// ─────────────────────────────────────────────────────────────────────────────
class _FlatButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _FlatButton({
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppColors.error : AppColors.ashGray;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withOpacity(0.18), width: 1),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTextStyles.button.copyWith(
            color: color,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scheduled Room Card
// ─────────────────────────────────────────────────────────────────────────────
class _ScheduledRoomCard extends StatefulWidget {
  final ScheduledRoomModel room;
  final UserModel? currentUser;
  final VoidCallback onTap;
  final VoidCallback onCancel;

  const _ScheduledRoomCard({
    required this.room,
    required this.currentUser,
    required this.onTap,
    required this.onCancel,
  });

  @override
  State<_ScheduledRoomCard> createState() => _ScheduledRoomCardState();
}

class _ScheduledRoomCardState extends State<_ScheduledRoomCard> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeUntil = widget.room.scheduledAt.difference(now);
    final isActive = widget.room.status == 'active';
    final isSoon = timeUntil.inMinutes <= 30 && timeUntil.inMinutes > 0;
    final room = widget.room;

    final thumbPath = room.videoThumbnailPath;
    final hasThumb = thumbPath != null &&
        thumbPath.isNotEmpty &&
        File(thumbPath).existsSync();

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 255,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF131313),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? AppColors.niorRed.withOpacity(0.45)
                : isSoon
                    ? AppColors.accentGold.withOpacity(0.35)
                    : const Color(0xFF1E1E1E),
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            if (hasThumb)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Opacity(
                  opacity: 0.22,
                  child: SizedBox.expand(
                    child:
                        Image.file(File(thumbPath!), fit: BoxFit.cover),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusBadge(status: room.status, isSoon: isSoon),
                  const Spacer(),
                  Text(
                    room.videoTitle,
                    style: AppTextStyles.bodyBold.copyWith(
                      color: AppColors.textWhite,
                      fontSize: 14,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  _Countdown(timeUntil: timeUntil, isActive: isActive),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        _typeIcon(room.streamType),
                        color: AppColors.ashGray.withOpacity(0.4),
                        size: 11,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _typeLabel(room.streamType),
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.ashGray.withOpacity(0.4),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: widget.onCancel,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.5),
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    color: AppColors.ashGray.withOpacity(0.55),
                    size: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'sync':  return Icons.sync_rounded;
      case 'hls':   return Icons.cast_rounded;
      default:      return Icons.mic_none_rounded;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'sync':  return 'Sync Watch';
      case 'hls':   return 'Video Stream';
      case 'audio': return 'Watch With a Friend';
      default:      return 'Stream';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status badge
// ─────────────────────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  final bool isSoon;

  const _StatusBadge({required this.status, required this.isSoon});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (status == 'active') {
      color = AppColors.niorRed;
      label = '● LIVE';
    } else if (isSoon) {
      color = AppColors.accentGold;
      label = '⏰ SOON';
    } else {
      color = AppColors.ashGray;
      label = 'SCHEDULED';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withOpacity(0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontSize: 9,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Countdown
// ─────────────────────────────────────────────────────────────────────────────
class _Countdown extends StatelessWidget {
  final Duration timeUntil;
  final bool isActive;

  const _Countdown({required this.timeUntil, required this.isActive});

  @override
  Widget build(BuildContext context) {
    if (isActive) {
      return Text(
        'Room is live now',
        style: AppTextStyles.caption.copyWith(
          color: AppColors.niorRed,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (timeUntil.isNegative) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 8,
            height: 8,
            child: CircularProgressIndicator(
              strokeWidth: 1.2,
              color: AppColors.accentGold,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Starting...',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.accentGold,
              fontSize: 11,
            ),
          ),
        ],
      );
    }
    final String label;
    if (timeUntil.inDays > 0) {
      label =
          '${timeUntil.inDays}d ${timeUntil.inHours.remainder(24)}h away';
    } else if (timeUntil.inHours > 0) {
      label =
          '${timeUntil.inHours}h ${timeUntil.inMinutes.remainder(60)}m away';
    } else {
      final m = timeUntil.inMinutes;
      final s = timeUntil.inSeconds.remainder(60);
      label = m > 0 ? '${m}m ${s}s away' : '${s}s away';
    }
    return Text(
      label,
      style: AppTextStyles.caption.copyWith(
        color: AppColors.textGray,
        fontSize: 11,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page route
// ─────────────────────────────────────────────────────────────────────────────
Route _pageRoute(Widget page) {
  return PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, anim, __, child) {
      final slide = Tween<Offset>(
        begin: const Offset(0.04, 0),
        end: Offset.zero,
      ).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
      final fade = CurvedAnimation(
        parent: anim,
        curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
      );
      return SlideTransition(
        position: slide,
        child: FadeTransition(opacity: fade, child: child),
      );
    },
  );
}