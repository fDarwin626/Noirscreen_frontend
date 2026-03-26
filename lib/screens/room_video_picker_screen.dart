import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import 'dart:io';
import '../constants/app_colors.dart';
import '../models/video_model.dart';
import '../providers/home_provider.dart';
import 'room_setup_screen.dart';

class RoomVideoPickerScreen extends ConsumerStatefulWidget {
  final String streamType;
  final VideoModel? preSelectedVideo;

  const RoomVideoPickerScreen({
    super.key,
    required this.streamType,
    this.preSelectedVideo,
  });

  @override
  ConsumerState<RoomVideoPickerScreen> createState() =>
      _RoomVideoPickerScreenState();
}

class _RoomVideoPickerScreenState extends ConsumerState<RoomVideoPickerScreen>
    with TickerProviderStateMixin {

  String? _activeCategory;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _showCategoryDropdown = false;
  bool _showSearch = false;
  int _currentPage = 0;

  // viewportFraction = 1.0 — one card fills the center
  // We manually add padding so sides of adjacent cards are barely visible
  late final PageController _pageController = PageController(
    viewportFraction: 1.0,
  );

  // Drives the title/meta fade when page changes
  late final AnimationController _titleController = AnimationController(
    duration: const Duration(milliseconds: 320),
    vsync: this,
  );
  late final Animation<double> _titleFade =
      CurvedAnimation(parent: _titleController, curve: Curves.easeOut);
  late final Animation<Offset> _titleSlide = Tween<Offset>(
    begin: const Offset(0, 0.3),
    end: Offset.zero,
  ).animate(CurvedAnimation(
      parent: _titleController, curve: Curves.easeOutCubic));

  final List<_Category> _categories = const [
    _Category(label: 'All',        value: null,         icon: Icons.apps_rounded),
    _Category(label: 'Downloaded', value: 'downloaded', icon: Icons.download_rounded),
    _Category(label: 'Movies',     value: 'movies',     icon: Icons.movie_rounded),
    _Category(label: 'Series',     value: 'series',     icon: Icons.tv_rounded),
    _Category(label: 'WhatsApp',   value: 'whatsapp',   icon: Icons.chat_rounded),
    _Category(label: 'Camera',     value: 'camera',     icon: Icons.camera_alt_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _titleController.forward();

    _pageController.addListener(() {
      final page = (_pageController.page ?? 0).round();
      if (page != _currentPage) {
        setState(() => _currentPage = page);
        _titleController.forward(from: 0);
      }
    });

    if (widget.preSelectedVideo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _go(widget.preSelectedVideo!);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  List<VideoModel> _filterVideos(List<VideoModel> all) {
    var filtered = all;
    if (_activeCategory != null) {
      if (_activeCategory == 'series') {
        filtered = filtered.where((v) => v.seriesId != null).toList();
      } else {
        filtered =
            filtered.where((v) => v.category == _activeCategory).toList();
      }
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      filtered =
          filtered.where((v) => v.title.toLowerCase().contains(q)).toList();
    }
    return filtered;
  }

  Future<void> _go(VideoModel video) async {
    setState(() {
      _showCategoryDropdown = false;
      _showSearch = false;
    });
    HapticFeedback.lightImpact();

    await Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 520),
        reverseTransitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, anim, __) =>
            RoomSetupScreen(video: video, streamType: widget.streamType),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(
              parent: anim,
              curve: const Interval(0.0, 0.55, curve: Curves.easeIn)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    final allAsync = ref.watch(allVideosProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: allAsync.when(
        data: (all) {
          final videos = _filterVideos(all);
          if (videos.isEmpty) return _buildEmpty();
          final current = videos[_currentPage.clamp(0, videos.length - 1)];
          return _buildBody(videos, current);
        },
        loading: () => _buildLoading(),
        error: (_, __) => _buildEmpty(),
      ),
    );
  }

  Widget _buildBody(List<VideoModel> videos, VideoModel current) {
    final size = MediaQuery.of(context).size;
    final statusH = MediaQuery.of(context).padding.top;

    // Card dimensions — tall poker-card proportions
    final cardWidth  = size.width * 0.62;
    final cardHeight = cardWidth * 1.55;

    return Stack(
      children: [
        // ── Blurred background — current poster bleeds behind everything ──
        Positioned.fill(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Blurred poster — actually visible, not hidden
              current.thumbnailPath != null
                  ? ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Image.file(
                        File(current.thumbnailPath!),
                        fit: BoxFit.cover,
                      ),
                    )
                  : const SizedBox.shrink(),
              // Light dark overlay — just enough contrast, poster still shows
              Container(color: Colors.black.withOpacity(0.38)),
            ],
          ),
        ),

        // ── Main column layout ────────────────────────────────────────
        Column(
          children: [
            SizedBox(height: statusH),

            // ── TOP BAR ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  // Back button
                  _circleBtn(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  // Category filter
                  _circleBtn(
                    icon: Icons.grid_view_rounded,
                    onTap: () => setState(() {
                      _showCategoryDropdown = !_showCategoryDropdown;
                      _showSearch = false;
                    }),
                    active: _activeCategory != null || _showCategoryDropdown,
                  ),
                  const Spacer(),
                  // Search
                  _circleBtn(
                    icon: Icons.search_rounded,
                    onTap: () => setState(() {
                      _showSearch = !_showSearch;
                      _showCategoryDropdown = false;
                      if (!_showSearch) {
                        _searchController.clear();
                        _searchQuery = '';
                      }
                    }),
                    active: _showSearch || _searchQuery.isNotEmpty,
                  ),
                ],
              ),
            ),

            // ── Search bar (slides in when active) ───────────────────
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              firstChild: const SizedBox(height: 0),
              secondChild: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: _buildSearchBar(),
              ),
              crossFadeState: _showSearch
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
            ),

            // ── TITLE + META (above the card, animated per swipe) ────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: SlideTransition(
                position: _titleSlide,
                child: FadeTransition(
                  opacity: _titleFade,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Category pill
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.niorRed.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: AppColors.niorRed.withOpacity(0.30),
                                  width: 0.7),
                            ),
                            child: Text(
                              current.category.toUpperCase(),
                              style: TextStyle(fontFamily: 'Inter', 
                                color: AppColors.niorRed,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          if (current.seasonEpisode != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              current.seasonEpisode!,
                              style: TextStyle(fontFamily: 'Inter', 
                                color: Colors.white.withOpacity(0.35),
                                fontSize: 11,
                              ),
                            ),
                          ],
                          const Spacer(),
                          // Page indicator
                          Text(
                            '${_currentPage + 1} / ${videos.length}',
                            style: TextStyle(fontFamily: 'Inter', 
                              color: Colors.white.withOpacity(0.25),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        current.title,
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
                    ],
                  ),
                ),
              ),
            ),

            // ── CARD CAROUSEL — centered, sides slightly peeking ─────
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: videos.length,
                itemBuilder: (context, index) {
                  return _buildCard(
                      videos[index], index, cardWidth, cardHeight);
                },
              ),
            ),

            // ── Progress dots ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 36, top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  videos.length.clamp(0, 8),
                  (i) {
                    final active = i == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 20 : 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white
                            : Colors.white.withOpacity(0.20),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),

        // ── Tap-away BEHIND the dropdown ─────────────────────────────
        if (_showCategoryDropdown)
          Positioned.fill(
            child: GestureDetector(
              onTap: () =>
                  setState(() => _showCategoryDropdown = false),
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
          ),

        // ── Category dropdown ON TOP so its taps aren't blocked ───────
        if (_showCategoryDropdown) _buildCategoryDropdown(statusH),
      ],
    );
  }

  // ── THE CARD — tall poker card proportions, curved, glassmorphism ──────────
  Widget _buildCard(
      VideoModel video, int index, double cardWidth, double cardHeight) {
    return GestureDetector(
      onTap: () => _go(video),
      child: Center(
        child: Container(
          width: cardWidth,
          height: cardHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.55),
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
                // Poster image
                Hero(
                  tag: 'poster_${video.id}',
                  child: video.thumbnailPath != null
                      ? Image.file(
                          File(video.thumbnailPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _posterPh(),
                        )
                      : _posterPh(),
                ),

                // Glass overlay — subtle, not heavy
                Positioned.fill(
                  child: BackdropFilter(
                    filter:
                        ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.55, 1.0],
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.65),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Progress bar at bottom of card if watched
                if ((video.watchProgress ?? 0) > 0 && video.duration > 0)
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(32)),
                      child: LinearProgressIndicator(
                        value: (video.watchProgress! / video.duration)
                            .clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: Colors.white.withOpacity(0.10),
                        valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.niorRed),
                      ),
                    ),
                  ),

                // Glass border shimmer
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
    );
  }

  // ── Circle button ──────────────────────────────────────────────────────────
  Widget _circleBtn({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? AppColors.niorRed.withOpacity(0.20)
                  : Colors.white.withOpacity(0.10),
              border: Border.all(
                color: active
                    ? AppColors.niorRed.withOpacity(0.45)
                    : Colors.white.withOpacity(0.15),
                width: 0.8,
              ),
            ),
            child: Icon(icon,
                color: active ? AppColors.niorRed : Colors.white,
                size: 18),
          ),
        ),
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: Colors.white.withOpacity(0.12), width: 0.8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(Icons.search_rounded,
                  color: Colors.white.withOpacity(0.35), size: 17),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(fontFamily: 'Inter', 
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w400),
                  cursorColor: AppColors.niorRed,
                  cursorWidth: 1.5,
                  decoration: InputDecoration(
                    hintText: 'Search videos...',
                    hintStyle: TextStyle(fontFamily: 'Inter', 
                        color: Colors.white.withOpacity(0.25),
                        fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (val) => setState(() {
                    _searchQuery = val;
                    _currentPage = 0;
                    if (_pageController.hasClients) {
                      _pageController.jumpToPage(0);
                    }
                  }),
                ),
              ),
              if (_searchQuery.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() {
                    _searchController.clear();
                    _searchQuery = '';
                  }),
                  child: Icon(Icons.close_rounded,
                      color: Colors.white.withOpacity(0.40), size: 16),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Category dropdown ──────────────────────────────────────────────────────
  Widget _buildCategoryDropdown(double topOffset) {
    return Positioned(
      // align below the category button
      top: topOffset + 62,
      left: 64,
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              width: 200,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: Colors.white.withOpacity(0.10), width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _categories.map((cat) {
                  final sel = _activeCategory == cat.value;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _activeCategory = cat.value;
                      _showCategoryDropdown = false;
                      _currentPage = 0;
                      if (_pageController.hasClients) {
                        _pageController.jumpToPage(0);
                      }
                    }),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: sel
                            ? Colors.white.withOpacity(0.05)
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                              color: Colors.white.withOpacity(0.05),
                              width: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(cat.icon,
                              color: sel
                                  ? AppColors.niorRed
                                  : Colors.white.withOpacity(0.35),
                              size: 16),
                          const SizedBox(width: 12),
                          Text(
                            cat.label,
                            style: TextStyle(fontFamily: 'Inter', 
                              color: sel
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.50),
                              fontSize: 13,
                              fontWeight: sel
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          if (sel) ...[
                            const Spacer(),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.niorRed),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _posterPh() => Container(
        color: const Color(0xFF1A1A1A),
        child: Center(
          child: Icon(Icons.movie_rounded,
              size: 48, color: Colors.white.withOpacity(0.06)),
        ),
      );

Widget _buildEmpty() {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.video_library_outlined,
                  size: 48, color: Colors.white.withOpacity(0.10)),
              const SizedBox(height: 14),
              Text(
                _searchQuery.isNotEmpty
                    ? 'No results for "$_searchQuery"'
                    : 'No videos here',
                style: TextStyle(fontFamily: 'Inter',
                    color: Colors.white.withOpacity(0.25), fontSize: 14),
              ),
              if (_searchQuery.isNotEmpty) ...[
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => setState(() {
                    _searchController.clear();
                    _searchQuery = '';
                    _showSearch = false;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.10), width: 0.8),
                    ),
                    child: Text('Clear search',
                        style: TextStyle(fontFamily: 'Inter',
                            color: Colors.white.withOpacity(0.40),
                            fontSize: 13)),
                  ),
                ),
              ],
            ],
          ),
        ),
        // Back button always visible
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 20,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.10),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.15), width: 0.8),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
  Widget _buildLoading() => Center(
        child: SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: AppColors.niorRed),
        ),
      );
}

class _Category {
  final String label;
  final String? value;
  final IconData icon;
  const _Category(
      {required this.label, required this.value, required this.icon});
}