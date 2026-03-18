import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noirscreen/constants/app_text_style.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:noirscreen/screens/room_screen.dart';
import 'dart:io';
import '../constants/app_colors.dart';
import '../providers/home_provider.dart';
import '../widgets/continue_watching_carousel.dart';
import '../widgets/video_category_row.dart';
import '../widgets/series_card_widget.dart';
import '../screens/series_details_screen.dart';
import '../services/auth_service.dart';
import '../services/api_services.dart';
import '../models/user_model.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final bool shouldRefresh;

  const HomeScreen({super.key, this.shouldRefresh = false});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  UserModel? _currentUser;
  bool _isLoadingUser = true;

  // Tracks which bottom nav tab is active
  // 0 = Home, 1 = Library, 2 = Rooms, 3 = Discover, 4 = Account
  int _currentNavIndex = 0;

  @override
  void initState() {
    super.initState();

    // Transparent status bar with white icons so video bleeds through
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );

    _loadUserData();

    if (widget.shouldRefresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        print('🔄 HOME SCREEN: Invalidating all providers (shouldRefresh=true)');
        ref.invalidate(allVideosProvider);
        ref.invalidate(downloadedVideosProvider);
        ref.invalidate(whatsappVideosProvider);
        ref.invalidate(mostStreamedProvider);
        ref.invalidate(recentlyWatchedProvider);
        ref.invalidate(moviesProvider);
        ref.invalidate(cameraVideosProvider);
        ref.invalidate(tvShowsProvider);
      });
    }
  }

  Future<void> _loadUserData() async {
    try {
      final authService = AuthService();
      final apiService = ApiService();
      final userId = await authService.getUserId();
      if (userId != null) {
        final user = await apiService.getUser(userId);
        if (mounted) {
          setState(() {
            _currentUser = user;
            _isLoadingUser = false;
          });
        }
      }
    } catch (e) {
      print('Error loading user: $e');
      if (mounted) setState(() => _isLoadingUser = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      // IndexedStack keeps all screens alive in memory
      // Switching tabs does not reload data or lose scroll position
      body: IndexedStack(
        index: _currentNavIndex,
        children: const [
          // 0 — Home
          _HomeContent(),
          // 1 — My Library (placeholder until we build it)
          _PlaceholderScreen(label: 'My Library'),
          // 2 — Rooms
          RoomsScreen(),
          // 3 — Discover (placeholder until we build it)
          _PlaceholderScreen(label: 'Discover'),
          // 4 — Account (placeholder until we build it)
          _PlaceholderScreen(label: 'Account'),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        border: Border(
          top: BorderSide(
            color: AppColors.ashGray.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(Icons.home_rounded, 'Home', 0),
          _buildNavItem(Icons.bookmark_rounded, 'My Library', 1),
          _buildNavItem(Icons.grid_view_rounded, 'Rooms', 2),
          _buildNavItem(Icons.auto_awesome_rounded, 'Discover', 3),
          _buildNavItemAvatar(4),
        ],
      ),
    );
  }

  // Regular nav item (icon + label)
  Widget _buildNavItem(IconData icon, String label, int index) {
    final isActive = _currentNavIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentNavIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive ? AppColors.niorRed : AppColors.textGray,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: isActive ? AppColors.niorRed : AppColors.textGray,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Avatar nav item for Account tab
  Widget _buildNavItemAvatar(int index) {
    final isActive = _currentNavIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentNavIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isActive ? AppColors.niorRed : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: _isLoadingUser
                    ? Icon(Icons.person_rounded,
                        color: AppColors.textGray, size: 20)
                    : _currentUser != null
                        ? _buildUserAvatar()
                        : Icon(Icons.person_rounded,
                            color: AppColors.textGray, size: 20),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Account',
              style: AppTextStyles.caption.copyWith(
                color: isActive ? AppColors.niorRed : AppColors.textGray,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserAvatar() {
    if (_currentUser!.avatarType == 'custom' &&
        _currentUser!.photoUrl != null) {
      return Image.network(
        '${ApiService.baseUrl}${_currentUser!.photoUrl}',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.person_rounded, color: AppColors.textGray, size: 20),
      );
    } else if (_currentUser!.avatarType == 'default' &&
        _currentUser!.avatarId != null) {
      final avatarId = _currentUser!.avatarId!;
      final isSvg = avatarId <= 9 || avatarId == 11 || avatarId == 12;
      final path =
          'assets/avatar/avatar ($avatarId).${isSvg ? 'svg' : 'png'}';
      if (isSvg) {
        return SvgPicture.asset(path, fit: BoxFit.cover);
      } else {
        return Image.asset(path, fit: BoxFit.cover);
      }
    }
    return Icon(Icons.person_rounded, color: AppColors.textGray, size: 20);
  }
}

// ── Home content ──────────────────────────────────────────────────────────────
// Separated into its own widget so IndexedStack can keep it alive
class _HomeContent extends ConsumerWidget {
  const _HomeContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentlyWatched = ref.watch(recentlyWatchedProvider);
    final tvShows = ref.watch(tvShowsProvider);
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return CustomScrollView(
      slivers: [
        // ── Hero carousel + floating header ─────────────────────────
        SliverToBoxAdapter(
          child: Stack(
            children: [
              // Full bleed carousel from top of screen
              recentlyWatched.when(
                data: (videos) {
                  if (videos.isEmpty) {
                    return Consumer(
                      builder: (context, ref, child) {
                        final downloaded = ref.watch(downloadedVideosProvider);
                        return downloaded.when(
                          data: (vids) => vids.isNotEmpty
                              ? ContinueWatchingCarousel(
                                  videos: vids.take(5).toList())
                              : const SizedBox.shrink(),
                          loading: () => const _CarouselSkeleton(),
                          error: (_, __) => const SizedBox.shrink(),
                        );
                      },
                    );
                  }
                  return ContinueWatchingCarousel(videos: videos);
                },
                loading: () => const _CarouselSkeleton(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              // Header floats at exactly status bar height
              Positioned(
                top: statusBarHeight,
                left: 0,
                right: 0,
                child: _buildHeader(context),
              ),
            ],
          ),
        ),

        SliverToBoxAdapter(child: const SizedBox(height: 32)),

        // ── Downloaded Videos ────────────────────────────────────────
        SliverToBoxAdapter(
          child: VideoCategoryRow(
            title: 'Downloaded Videos',
            provider: downloadedVideosProvider,
          ),
        ),

        SliverToBoxAdapter(child: const SizedBox(height: 24)),

        // ── TV Shows glassmorphism cards ─────────────────────────────
        SliverToBoxAdapter(
          child: tvShows.when(
            data: (seriesList) {
              if (seriesList.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'TV SHOWS',
                      style: AppTextStyles.header3.copyWith(
                        color: AppColors.textWhite,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 320,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: seriesList.length,
                      itemBuilder: (context, index) {
                        final series = seriesList[index];
                        final episodesAsync =
                            ref.watch(episodesProvider(series.id));
                        return episodesAsync.when(
                          data: (episodes) => SeriesCardWidget(
                            series: series,
                            previewEpisodes: episodes,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    SeriesDetailScreen(series: series),
                              ),
                            ),
                          ),
                          loading: () => _buildSeriesCardSkeleton(),
                          error: (_, __) => const SizedBox.shrink(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ),


        // ── Most Streamed ────────────────────────────────────────────
        SliverToBoxAdapter(
          child: VideoCategoryRow(
            title: 'Most Streamed',
            provider: mostStreamedProvider,
          ),
        ),

        SliverToBoxAdapter(child: const SizedBox(height: 24)),

        // ── WhatsApp Videos ──────────────────────────────────────────
        SliverToBoxAdapter(
          child: VideoCategoryRow(
            title: 'WhatsApp Videos',
            provider: whatsappVideosProvider,
          ),
        ),

        SliverToBoxAdapter(child: const SizedBox(height: 24)),

        // ── Movies ───────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: VideoCategoryRow(
            title: 'Movies',
            provider: moviesProvider,
          ),
        ),

        SliverToBoxAdapter(child: const SizedBox(height: 24)),

        // ── Camera Videos ────────────────────────────────────────────
        SliverToBoxAdapter(
          child: VideoCategoryRow(
            title: 'Camera Videos',
            provider: cameraVideosProvider,
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.black.withOpacity(0.5),
            Colors.transparent,
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Image.asset(
            'assets/images/NOIR logo white.png',
            height: 32,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Text(
              'NOIRSCREEN',
              style: AppTextStyles.bodyBold.copyWith(
                color: AppColors.niorRed,
                fontSize: 13,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.cast_rounded,
                color: AppColors.textWhite, size: 24),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.search_rounded,
                color: AppColors.textWhite, size: 24),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSeriesCardSkeleton() {
    return Container(
      width: 220,
      height: 320,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: AppColors.darkGray,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

// ── Carousel skeleton ─────────────────────────────────────────────────────────
class _CarouselSkeleton extends StatelessWidget {
  const _CarouselSkeleton();

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.62;
    return Container(
      height: height,
      color: AppColors.darkGray,
      child: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.niorRed),
        ),
      ),
    );
  }
}

// ── Placeholder for screens not built yet ────────────────────────────────────
class _PlaceholderScreen extends StatelessWidget {
  final String label;
  const _PlaceholderScreen({required this.label});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Center(
        child: Text(
          label,
          style: AppTextStyles.header3.copyWith(
            color: AppColors.ashGray,
          ),
        ),
      ),
    );
  }
}