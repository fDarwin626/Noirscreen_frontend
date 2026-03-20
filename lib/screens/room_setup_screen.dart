import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noirscreen/providers/rooms_provider.dart';
import 'dart:ui';
import 'dart:io';
import '../constants/app_colors.dart';
import '../models/video_model.dart';
import '../models/scheduled_room_model.dart';
import '../services/rooms_service.dart';
import '../utils/filename_parser.dart';

class RoomSetupScreen extends ConsumerStatefulWidget {
  final VideoModel video;
  final String streamType;

  const RoomSetupScreen({
    super.key,
    required this.video,
    required this.streamType,
  });

  @override
  ConsumerState<RoomSetupScreen> createState() => _RoomSetupScreenState();
}

class _RoomSetupScreenState extends ConsumerState<RoomSetupScreen>
    with TickerProviderStateMixin {

  bool _isScheduled = false;
  DateTime _selectedDateTime =
      DateTime.now().add(const Duration(minutes: 10));
  int _minutesFromNow = 10;
  bool _isCreatingLink = false;
  ScheduledRoomModel? _createdRoom;
  bool _linkCopied = false;

  final RoomsService _roomsService = RoomsService();

  late final AnimationController _panelController = AnimationController(
    duration: const Duration(milliseconds: 460),
    vsync: this,
  );
  late final Animation<double> _panelFade = CurvedAnimation(
    parent: _panelController,
    curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
  );
  late final Animation<Offset> _panelSlide = Tween<Offset>(
    begin: const Offset(0, 0.08),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _panelController,
    curve: Curves.easeOutCubic,
  ));

  late final AnimationController _backController = AnimationController(
    duration: const Duration(milliseconds: 280),
    vsync: this,
  );
  late final Animation<double> _backFade =
      CurvedAnimation(parent: _backController, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 140), () {
      if (mounted) {
        _backController.forward();
        _panelController.forward();
      }
    });
  }

  @override
  void dispose() {
    _panelController.dispose();
    _backController.dispose();
    super.dispose();
  }

  String get _typeLabel {
    switch (widget.streamType) {
      case 'hls':      return 'Video Streaming';
      case 'sync':     return 'Sync Watch';
      case 'audio':    return 'Audio Streaming';
      case 'download': return 'Share & Download';
      default:         return 'Stream';
    }
  }

  String get _typeGuide {
    switch (widget.streamType) {
      case 'hls':
        return 'You stream the video from your device. Friends join and watch in real time — only you need the file.';
      case 'sync':
        return 'Everyone has this video. No video data is sent — just sync commands keep everyone in time.';
      case 'audio':
        return 'Voice chat while watching. Great for low-data connections.';
      case 'download':
        return 'Friends can request to download this video with your permission.';
      default:
        return 'Share and watch together.';
    }
  }

  // ── Create room ─────────────────────────────────────────────────────────────
  Future<void> _createRoom() async {
    if (_isCreatingLink) return;
    setState(() => _isCreatingLink = true);
    HapticFeedback.lightImpact();

    try {
      final now = DateTime.now();

      // scheduledTime is either the slider value (NOW mode)
      // or the date/time the user picked (SCHEDULE mode)
      // In NOW mode we add 2min10s — the extra 10s is a buffer so the
      // backend validation (which also checks >= 2 min) does not fail
      // due to the few hundred milliseconds of network travel time
      final scheduledTime = _isScheduled
          ? _selectedDateTime
          : now.add(const Duration(minutes: 2, seconds: 10));

      // Only validate minimum time in SCHEDULE mode
      // In NOW mode the time is always now + 2min10s so it always passes
      if (_isScheduled && scheduledTime.difference(now).inMinutes < 2) {
        _err('Schedule at least 2 minutes from now');
        return;
      }

      // Maximum 5 days in advance — applies to both modes
      if (scheduledTime.difference(now).inDays > 5) {
        _err('Cannot schedule more than 5 days ahead');
        return;
      }

      final hash = FileNameParser.generateVideoId(widget.video.filePath);

      final room = await _roomsService.createRoom(
        videoHash: hash,
        videoTitle: widget.video.title,
        videoThumbnailPath: widget.video.thumbnailPath ?? '',
        videoFilePath: widget.video.filePath,
        streamType: widget.streamType,
        scheduledAt: scheduledTime,
        videoDuration: widget.video.duration,
      );

      if (mounted && room != null) {
        // Attach the local file path to the room model so when the
        // owner taps the live card the video player knows which file to play
        setState(() => _createdRoom = room.copyWith(
          videoFilePath: widget.video.filePath,
        ));
      }
    } catch (e) {
      _err(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isCreatingLink = false);
    }
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        msg,
        style: const TextStyle(
            fontFamily: 'Inter', color: Colors.white, fontSize: 13),
      ),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _copyLink() {
    if (_createdRoom == null) return;
    Clipboard.setData(ClipboardData(text: _createdRoom!.shareableLink));
    HapticFeedback.lightImpact();
    setState(() => _linkCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _linkCopied = false);
    });
  }

  // ── Date picker (SCHEDULE mode) ────────────────────────────────────────────
  Future<void> _pickDateTime() async {
    final now = DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: now.add(const Duration(minutes: 2)),
      lastDate: now.add(const Duration(days: 5)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.niorRed,
            surface: const Color(0xFF141414),
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: const Color(0xFF141414),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final picked = await _showTimeScrollPicker(date);
    if (picked == null || !mounted) return;

    if (picked.difference(now).inMinutes < 2) {
      _err('Must be at least 2 minutes from now');
      return;
    }
    setState(() => _selectedDateTime = picked);
  }

  // ── Custom scroll-wheel time picker ───────────────────────────────────────
  // Replaces Flutter's default clock face with ugly green AM/PM
  Future<DateTime?> _showTimeScrollPicker(DateTime date) async {
    int selHour = _selectedDateTime.hour > 12
        ? _selectedDateTime.hour - 12
        : (_selectedDateTime.hour == 0 ? 12 : _selectedDateTime.hour);
    int selMinute = (_selectedDateTime.minute ~/ 5) * 5;
    bool isAM = _selectedDateTime.hour < 12;

    final hourCtrl = FixedExtentScrollController(initialItem: selHour - 1);
    final minCtrl = FixedExtentScrollController(initialItem: selMinute ~/ 5);

    final result = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.80),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withOpacity(0.10),
                    width: 0.8,
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'PICK A TIME',
                    style: TextStyle(
                      fontFamily: 'BebasNeue',
                      color: Colors.white.withOpacity(0.50),
                      fontSize: 14,
                      letterSpacing: 2.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    height: 180,
                    child: Row(
                      children: [
                        // Hour wheel 1–12
                        Expanded(
                          child: _scrollWheel(
                            controller: hourCtrl,
                            itemCount: 12,
                            label: (i) => (i + 1).toString().padLeft(2, '0'),
                            onChanged: (i) =>
                                setModal(() => selHour = i + 1),
                          ),
                        ),

                        // Colon separator
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            ':',
                            style: TextStyle(
                              fontFamily: 'BebasNeue',
                              color: Colors.white.withOpacity(0.60),
                              fontSize: 32,
                            ),
                          ),
                        ),

                        // Minute wheel 00–55 in steps of 5
                        Expanded(
                          child: _scrollWheel(
                            controller: minCtrl,
                            itemCount: 12,
                            label: (i) =>
                                (i * 5).toString().padLeft(2, '0'),
                            onChanged: (i) =>
                                setModal(() => selMinute = i * 5),
                          ),
                        ),

                        const SizedBox(width: 16),

                        // AM / PM stacked buttons
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _ampmBtn(
                              label: 'AM',
                              selected: isAM,
                              onTap: () => setModal(() => isAM = true),
                            ),
                            const SizedBox(height: 8),
                            _ampmBtn(
                              label: 'PM',
                              selected: !isAM,
                              onTap: () => setModal(() => isAM = false),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Confirm button
                  GestureDetector(
                    onTap: () {
                      int h24;
                      if (isAM) {
                        h24 = selHour == 12 ? 0 : selHour;
                      } else {
                        h24 = selHour == 12 ? 12 : selHour + 12;
                      }
                      Navigator.pop(
                        ctx,
                        DateTime(
                            date.year, date.month, date.day, h24, selMinute),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.09),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.15),
                          width: 0.8,
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'CONFIRM',
                          style: TextStyle(
                            fontFamily: 'BebasNeue',
                            color: Colors.white,
                            fontSize: 16,
                            letterSpacing: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    hourCtrl.dispose();
    minCtrl.dispose();
    return result;
  }

  Widget _scrollWheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int) label,
    required ValueChanged<int> onChanged,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 48,
      diameterRatio: 1.4,
      perspective: 0.003,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: itemCount,
        builder: (context, i) {
          final active = controller.selectedItem == i;
          return Center(
            child: Text(
              label(i),
              style: TextStyle(
                fontFamily: 'BebasNeue',
                color: active
                    ? Colors.white
                    : Colors.white.withOpacity(0.18),
                fontSize: active ? 32 : 22,
                letterSpacing: 1,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _ampmBtn({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 52,
        height: 40,
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withOpacity(0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Colors.white.withOpacity(0.30)
                : Colors.white.withOpacity(0.08),
            width: 0.8,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'BebasNeue',
              color: selected
                  ? Colors.white
                  : Colors.white.withOpacity(0.25),
              fontSize: 15,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  // ── NOW slider — 2 min to 24 hrs ──────────────────────────────────────────
  Widget _buildNowSlider() {
    final h = _minutesFromNow ~/ 60;
    final m = _minutesFromNow % 60;
    final label = _minutesFromNow < 60
        ? '$_minutesFromNow min from now'
        : m == 0
            ? '${h}h from now'
            : '${h}h ${m}m from now';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.timer_rounded, color: AppColors.niorRed, size: 13),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.niorRed,
            inactiveTrackColor: Colors.white.withOpacity(0.10),
            thumbColor: Colors.white,
            overlayColor: AppColors.niorRed.withOpacity(0.15),
            trackHeight: 2,
            thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape:
                const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: _minutesFromNow.toDouble(),
            min: 2,
            max: 1440,
            onChanged: (val) {
              int snapped;
              if (val <= 30) {
                snapped = (val / 5).round() * 5;
                if (snapped < 2) snapped = 2;
              } else if (val <= 120) {
                snapped = (val / 15).round() * 15;
              } else {
                snapped = (val / 30).round() * 30;
              }
              setState(() {
                _minutesFromNow = snapped.clamp(2, 1440);
                _selectedDateTime = DateTime.now()
                    .add(Duration(minutes: _minutesFromNow));
              });
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '2 min',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.white.withOpacity(0.18),
                  fontSize: 9,
                ),
              ),
              Text(
                '24 hrs',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.white.withOpacity(0.18),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    final size = MediaQuery.of(context).size;
    final statusH = MediaQuery.of(context).padding.top;
    final cardWidth = size.width * 0.62;
    final cardHeight = cardWidth * 1.55;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          // ── Blurred ambient background ─────────────────────────────
          Positioned.fill(
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.video.thumbnailPath != null
                    ? ImageFiltered(
                        imageFilter:
                            ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Image.file(
                          File(widget.video.thumbnailPath!),
                          fit: BoxFit.cover,
                        ),
                      )
                    : const SizedBox.shrink(),
                Container(color: Colors.black.withOpacity(0.38)),
              ],
            ),
          ),

          // ── Main scrollable body ───────────────────────────────────
          SingleChildScrollView(
            padding: EdgeInsets.only(top: statusH + 60, bottom: 50),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title + badges above card ──────────────────────
                SlideTransition(
                  position: _panelSlide,
                  child: FadeTransition(
                    opacity: _panelFade,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            children: [
                              _pill(widget.video.category.toUpperCase(),
                                  color: AppColors.niorRed),
                              _pill(_typeLabel.toUpperCase()),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.video.title,
                            style: const TextStyle(
                              fontFamily: 'BebasNeue',
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.normal,
                              letterSpacing: 1.0,
                              height: 1.1,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.video.seasonEpisode != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.video.seasonEpisode!,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: Colors.white.withOpacity(0.35),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Poster card ────────────────────────────────────
                Center(
                  child: Hero(
                    tag: 'poster_${widget.video.id}',
                    child: Container(
                      width: cardWidth,
                      height: cardHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.60),
                            blurRadius: 40,
                            offset: const Offset(0, 16),
                            spreadRadius: -4,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            widget.video.thumbnailPath != null
                                ? Image.file(
                                    File(widget.video.thumbnailPath!),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _posterPh(),
                                  )
                                : _posterPh(),
                            // Bottom scrim
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              height: cardHeight * 0.35,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withOpacity(0.60),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Progress bar if partially watched
                            if ((widget.video.watchProgress ?? 0) > 0 &&
                                widget.video.duration > 0)
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: LinearProgressIndicator(
                                  value: (widget.video.watchProgress! /
                                          widget.video.duration)
                                      .clamp(0.0, 1.0),
                                  minHeight: 3,
                                  backgroundColor:
                                      Colors.white.withOpacity(0.10),
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(
                                          AppColors.niorRed),
                                ),
                              ),
                            // Glass border
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(32),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.12),
                                    width: 0.8,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Setup or Link panel ────────────────────────────
                SlideTransition(
                  position: _panelSlide,
                  child: FadeTransition(
                    opacity: _panelFade,
                    child: _createdRoom != null
                        ? _buildLinkPanel()
                        : _buildSetupPanel(),
                  ),
                ),
              ],
            ),
          ),

          // ── Back button ───────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: FadeTransition(
                opacity: _backFade,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      behavior: HitTestBehavior.opaque,
                      child: ClipOval(
                        child: BackdropFilter(
                          filter:
                              ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.10),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.15),
                                width: 0.8,
                              ),
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                              size: 17,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Setup panel ────────────────────────────────────────────────────────────
  Widget _buildSetupPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // About this stream glass card
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.10),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel('ABOUT THIS STREAM'),
                    const SizedBox(height: 8),
                    Text(
                      _typeGuide,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.white.withOpacity(0.50),
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // When glass card
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.10),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel('WHEN'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _whenBtn('NOW', !_isScheduled,
                            () => setState(() => _isScheduled = false)),
                        const SizedBox(width: 10),
                        _whenBtn('SCHEDULE', _isScheduled,
                            () => setState(() => _isScheduled = true)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!_isScheduled)
                      _buildNowSlider()
                    else ...[
                      _buildDatePicker(),
                      const SizedBox(height: 4),
                      Text(
                        'Min 2 min · Max 5 days',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: Colors.white.withOpacity(0.18),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Create room CTA button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: GestureDetector(
              onTap: _isCreatingLink ? null : _createRoom,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    decoration: BoxDecoration(
                      color: _isCreatingLink
                          ? Colors.white.withOpacity(0.08)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: _isCreatingLink
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Colors.white.withOpacity(0.40),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.link_rounded,
                                    color: Colors.black, size: 16),
                                SizedBox(width: 8),
                                Text(
                                  'CREATE ROOM',
                                  style: TextStyle(
                                    fontFamily: 'BebasNeue',
                                    color: Colors.black,
                                    fontSize: 16,
                                    fontWeight: FontWeight.normal,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: TextStyle(
          fontFamily: 'Inter',
          color: Colors.white.withOpacity(0.22),
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.2,
        ),
      );

  Widget _whenBtn(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 40,
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? Colors.white.withOpacity(0.25)
                  : Colors.white.withOpacity(0.08),
              width: 0.8,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                color: selected
                    ? Colors.white
                    : Colors.white.withOpacity(0.30),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: _pickDateTime,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.niorRed.withOpacity(0.25),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded,
                color: AppColors.niorRed, size: 14),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _fmtDate(_selectedDateTime),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'in ${_fmtCountdown(_selectedDateTime)}',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white.withOpacity(0.30),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit_rounded,
                color: Colors.white.withOpacity(0.20), size: 13),
          ],
        ),
      ),
    );
  }

  // ── Link panel ─────────────────────────────────────────────────────────────
  Widget _buildLinkPanel() {
    final room = _createdRoom!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Success glass card
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.10),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'ROOM CREATED',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.success,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Starts in ${_fmtCountdown(room.scheduledAt)}',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.accentGold,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      room.shareableLink,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.white.withOpacity(0.40),
                        fontSize: 11,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _actionBtn(
                            label: _linkCopied ? 'COPIED' : 'COPY LINK',
                            icon: _linkCopied
                                ? Icons.check_rounded
                                : Icons.copy_rounded,
                            onTap: _copyLink,
                            filled: true,
                            success: _linkCopied,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _actionBtn(
                            label: 'SHARE',
                            icon: Icons.share_rounded,
                            onTap: () {},
                            filled: false,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Receipt glass card
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.10),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  children: [
                    _receipt('VIDEO', widget.video.title),
                    _receipt('TYPE', _typeLabel),
                    _receipt('STARTS', _fmtDate(room.scheduledAt)),
                    _receipt('EXPIRES', _fmtDate(room.linkExpiresAt)),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Done button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: GestureDetector(
              onTap: () {
                ref.invalidate(scheduledRoomsProvider);
                Navigator.popUntil(context, (r) => r.isFirst);
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text(
                        'DONE',
                        style: TextStyle(
                          fontFamily: 'BebasNeue',
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, {Color? color}) {
    final c = color ?? Colors.white.withOpacity(0.50);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.28), width: 0.7),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Inter',
          color: c,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
    );
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required bool filled,
    bool success = false,
  }) {
    final c = success ? AppColors.success : Colors.white.withOpacity(0.60);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: filled
              ? (success
                  ? AppColors.success.withOpacity(0.12)
                  : Colors.white.withOpacity(0.09))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: success
                ? AppColors.success.withOpacity(0.28)
                : Colors.white.withOpacity(0.10),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: c, size: 13),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                color: c,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receipt(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              color: Colors.white.withOpacity(0.22),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'Inter',
                color: AppColors.accentGold,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _posterPh() => Container(
        color: const Color(0xFF1A1A1A),
        child: Center(
          child: Icon(
            Icons.movie_rounded,
            size: 48,
            color: Colors.white.withOpacity(0.06),
          ),
        ),
      );

  String _fmtDate(DateTime dt) {
    final now = DateTime.now();
    final today = dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    if (today) return 'Today $h:$m';
    const mo = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${mo[dt.month]} ${dt.day}  $h:$m';
  }

  String _fmtCountdown(DateTime dt) {
    final d = dt.difference(DateTime.now());
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}m';
  }
}