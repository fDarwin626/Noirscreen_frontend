import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class _RoomsScreenState extends ConsumerState<RoomsScreen> {
  ScheduledRoomModel? _lastCompletedRoom;
  UserModel? _currentUser;
  bool _loadingUser = true;
  final RoomsService _roomsService = RoomsService();
  Timer? _refreshTimer;
  final TextEditingController _joinLinkController = TextEditingController();
  bool _isJoining = false;

@override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadLastCompletedRoom();
    // Immediately invalidate on first load so fresh data always comes in
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(scheduledRoomsProvider);
    });
    // Then refresh every 15 seconds so LIVE badge appears fast
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) ref.invalidate(scheduledRoomsProvider);
    });
  }

@override
  void dispose() {
    _refreshTimer?.cancel();
    _joinLinkController.dispose();
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
      print('❌ ROOMS SCREEN: Failed to load user - $e');
      if (mounted) setState(() => _loadingUser = false);
    }
  }

  Future<void> _loadLastCompletedRoom() async {
    try {
      final rooms = await _roomsService.getCompletedRooms();
      if (rooms.isNotEmpty && mounted) {
        setState(() => _lastCompletedRoom = rooms.first);
      }
    } catch (e) {
      print('❌ ROOMS: load completed - $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduledRooms = ref.watch(scheduledRoomsProvider);

    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(
              child: scheduledRooms.when(
                data: (rooms) => rooms.isEmpty
                    ? const SizedBox.shrink()
                    : _buildScheduledRoomsSection(rooms),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),
            SliverToBoxAdapter(child: _buildStreamingTypesGrid()),
            SliverToBoxAdapter(child: _buildBottomIllustration()),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
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
          const SizedBox(height: 6),
          Text(
            'Watch together. Anywhere. In sync.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.ashGray,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          _buildJoinRoomField(),
        ],
      ),
    );
  }

  Widget _buildScheduledRoomsSection(List<ScheduledRoomModel> rooms) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
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
            itemCount: rooms.length,
            itemBuilder: (context, index) =>
                _buildScheduledRoomCard(rooms[index]),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildScheduledRoomCard(ScheduledRoomModel room) {
    final now = DateTime.now();
    final timeUntil = room.scheduledAt.difference(now);
    final isActive = room.status == 'active';
    final isSoon = timeUntil.inMinutes <= 30 && timeUntil.inMinutes > 0;

    return GestureDetector(
      onTap: () {
        if (!isActive) return;
        if (_currentUser == null) return;

        final isOwner = room.hostId == _currentUser!.userId;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RoomWatchScreen(
              room: room,
              currentUser: _currentUser!,
              isOwner: isOwner,
              localFilePath: isOwner ? room.videoFilePath : null,
              hlsStreamUrl: isOwner
                  ? null
                  : '${ApiService.baseUrl}/api/rooms/${room.roomId}/stream.m3u8',
            ),
          ),
        );
      },
      child: Container(
        width: 260,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: AppColors.darkGray,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? AppColors.niorRed.withOpacity(0.5)
                : isSoon
                ? AppColors.accentGold.withOpacity(0.4)
                : AppColors.ashGray.withOpacity(0.1),
            width: 0.8,
          ),
        ),
        child: Stack(
          children: [
            if (room.videoThumbnailPath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Opacity(
                  opacity: 0.35,
                  child: SizedBox.expand(
                    child: Image.file(
                      File(room.videoThumbnailPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusBadge(room.status, isSoon),
                  const Spacer(),
                  Text(
                    room.videoTitle,
                    style: AppTextStyles.bodyBold.copyWith(
                      color: AppColors.textWhite,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  _buildCountdown(room, timeUntil, isActive),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        _streamTypeIcon(room.streamType),
                        color: AppColors.ashGray,
                        size: 12,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _streamTypeLabel(room.streamType),
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.ashGray,
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
                onTap: () => _showCancelDialog(room),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.black.withOpacity(0.6),
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    color: AppColors.textGray,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status, bool isSoon) {
    Color color;
    String label;
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
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4), width: 0.6),
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

  Widget _buildCountdown(
    ScheduledRoomModel room,
    Duration timeUntil,
    bool isActive,
  ) {
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
      // Time has passed — waiting for backend activation (up to 30s)
      // Invalidate provider to check for status update
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.invalidate(scheduledRoomsProvider);
      });
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
    
    String countdown;
    if (timeUntil.inDays > 0) {
      countdown =
          '${timeUntil.inDays}d ${timeUntil.inHours.remainder(24)}h away';
    } else if (timeUntil.inHours > 0) {
      countdown =
          '${timeUntil.inHours}h ${timeUntil.inMinutes.remainder(60)}m away';
    } else {
      countdown = '${timeUntil.inMinutes}m away';
    }
    return Text(
      countdown,
      style: AppTextStyles.caption.copyWith(
        color: AppColors.textGray,
        fontSize: 11,
      ),
    );
  }

  IconData _streamTypeIcon(String type) {
    switch (type) {
      case 'sync':
        return Icons.sync_rounded;
      case 'hls':
        return Icons.cast_rounded;
      default:
        return Icons.stream_rounded;
    }
  }

  String _streamTypeLabel(String type) {
    switch (type) {
      case 'sync':
        return 'Sync Watch';
      case 'hls':
        return 'Video Stream';
      case 'audio':
        return 'Audio Stream';
      default:
        return 'Stream';
    }
  }

  void _showCancelDialog(ScheduledRoomModel room) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.darkGray,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Cancel Room?',
          style: AppTextStyles.bodyBold.copyWith(color: AppColors.textWhite),
        ),
        content: Text(
          'This will cancel the scheduled room for "${room.videoTitle}". '
          'Anyone with the link will no longer be able to join.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textGray,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Keep It',
              style: AppTextStyles.button.copyWith(
                color: AppColors.ashGray,
                fontSize: 14,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await _roomsService.cancelRoom(room.roomId);
              if (success && mounted) {
                ref.invalidate(scheduledRoomsProvider);
              }
            },
            child: Text(
              'Cancel Room',
              style: AppTextStyles.button.copyWith(
                color: AppColors.error,
                fontSize: 14,
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Invalid room link format',
            style: TextStyle(fontFamily: 'Inter', color: Colors.white)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }
    setState(() => _isJoining = true);
    try {
      final room = await _roomsService.joinViaLink(link);
      if (room == null || !mounted) return;
      if (_currentUser == null) return;
      _joinLinkController.clear();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RoomWatchScreen(
            room: room,
            currentUser: _currentUser!,
            isOwner: false,
            localFilePath: null,
            hlsStreamUrl:
                '${ApiService.baseUrl}/api/rooms/${room.roomId}/stream.m3u8',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceAll('Exception: ', ''),
            style: const TextStyle(fontFamily: 'Inter', color: Colors.white)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  Widget _buildJoinRoomField() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.darkGray.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.ashGray.withOpacity(0.12),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded, color: AppColors.ashGray, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _joinLinkController,
              style: const TextStyle(
                fontFamily: 'Inter', color: Colors.white, fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Paste room link to join...',
                hintStyle: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.ashGray.withOpacity(0.45),
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.niorRed.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.niorRed.withOpacity(0.40), width: 0.8,
                ),
              ),
              child: _isJoining
                  ? SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: AppColors.niorRed),
                    )
                  : Text(
                      'JOIN',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.niorRed,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamingTypesGrid() {
    final types = [
      _StreamType(
        icon: Icons.mic_none_rounded,
        label: 'Audio\nStreaming',
        subtitle: 'Voice + sync',
        type: 'audio',
      ),
      _StreamType(
        icon: Icons.play_circle_outline_rounded,
        label: 'Video\nStreaming',
        subtitle: 'Owner streams',
        type: 'hls',
      ),
      _StreamType(
        icon: Icons.sync_rounded,
        label: 'Sync\nWatch',
        subtitle: 'Both have file',
        type: 'sync',
      ),
      _StreamType(
        icon: Icons.download_outlined,
        label: 'Share &\nDownload',
        subtitle: 'Request access',
        type: 'download',
      ),
    ];

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
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.35,
            ),
            itemCount: types.length,
            itemBuilder: (context, index) => _buildStreamTypeCard(types[index]),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamTypeCard(_StreamType type) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RoomVideoPickerScreen(streamType: type.type),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF131313),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E1E1E), width: 0.8),
        ),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(type.icon, color: AppColors.textWhite, size: 24),
            const Spacer(),
            Text(
              type.label,
              style: AppTextStyles.bodyBold.copyWith(
                color: const Color(0xFFE8E8E8),
                fontSize: 13.5,
                height: 1.25,
                letterSpacing: -0.1,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(
                height: 1,
                thickness: 0.5,
                color: Color(0xFF1E1E1E),
              ),
            ),
            Text(
              type.subtitle.toUpperCase(),
              style: AppTextStyles.caption.copyWith(
                color: const Color(0xFF3A3A3A),
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomIllustration() {
    if (_lastCompletedRoom != null) {
      return _buildCompletedRoomCard(_lastCompletedRoom!);
    }
    return Container(
      height: 200,
      margin: const EdgeInsets.fromLTRB(20, 32, 20, 0),
      decoration: BoxDecoration(
        color: AppColors.darkGray.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.ashGray.withOpacity(0.08),
          width: 0.8,
        ),
      ),
      child: Center(
        child: Image.asset(
          'assets/images/streamer.png',
          width: 180,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _buildCompletedRoomCard(ScheduledRoomModel room) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 32, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkGray.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.ashGray.withOpacity(0.08),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          if (room.videoThumbnailPath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(room.videoThumbnailPath!),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LAST STREAMED',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.ashGray,
                    fontSize: 9,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  room.videoTitle,
                  style: AppTextStyles.bodyBold.copyWith(
                    color: AppColors.textWhite,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _streamTypeLabel(room.streamType),
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.ashGray,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AppColors.success.withOpacity(0.3),
                width: 0.8,
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
}

class _StreamType {
  final IconData icon;
  final String label;
  final String subtitle;
  final String type;

  const _StreamType({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.type,
  });
}
