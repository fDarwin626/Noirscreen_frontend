import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noirscreen/constants/app_text_style.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:noirscreen/screens/room_screen.dart';
import 'package:noirscreen/services/video_manager_service.dart';
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
  int _currentNavIndex = 0;

  @override
  void initState() {
    super.initState();

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
          setState(() { _currentUser = user; _isLoadingUser = false; });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingUser = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // BUG 3 FIX: read the bottom system inset so our nav bar sits above
    // the 3-button nav (circle/square/triangle) on phones that use it.
    // On gesture-nav phones this is 0. On 3-button phones it's ~48dp.
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.black,
      body: IndexedStack(
        index: _currentNavIndex,
        children: const [
          _HomeContent(),
          _PlaceholderScreen(label: 'My Library'),
          RoomsScreen(),
          _PlaceholderScreen(label: 'Discover'),
          _PlaceholderScreen(label: 'Account'),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(context, bottomInset),
    );
  }

  Widget _buildBottomNav(BuildContext context, double bottomInset) {
    // BUG 3 FIX: add bottomInset as bottom padding so the nav items sit
    // above the system navigation bar on 3-button phones.
    // The extra padding pushes items up exactly far enough so they
    // don't overlap the circle/square/triangle buttons.
    return Container(
      // 70 = icon + label height, bottomInset = system nav bar height
      height: 70 + bottomInset,
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        border: Border(
          top: BorderSide(
            color: AppColors.ashGray.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Padding(
        // Push nav items up by the system nav bar height
        padding: EdgeInsets.only(bottom: bottomInset),
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
      ),
    );
  }

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
            Icon(icon,
                color: isActive ? AppColors.niorRed : AppColors.textGray,
                size: 24),
            const SizedBox(height: 4),
            Text(label,
                style: AppTextStyles.caption.copyWith(
                  color: isActive ? AppColors.niorRed : AppColors.textGray,
                  fontSize: 10,
                )),
          ],
        ),
      ),
    );
  }

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
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isActive ? AppColors.niorRed : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: _isLoadingUser
                    ? Icon(Icons.person_rounded, color: AppColors.textGray, size: 20)
                    : _currentUser != null
                        ? _buildUserAvatar()
                        : Icon(Icons.person_rounded, color: AppColors.textGray, size: 20),
              ),
            ),
            const SizedBox(height: 4),
            Text('Account',
                style: AppTextStyles.caption.copyWith(
                  color: isActive ? AppColors.niorRed : AppColors.textGray,
                  fontSize: 10,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildUserAvatar() {
    if (_currentUser!.avatarType == 'custom' && _currentUser!.photoUrl != null) {
      final photo = _currentUser!.photoUrl!;
      if (photo.startsWith('data:image')) {
        try {
          final base64Str = photo.contains(',') ? photo.split(',').last : photo;
          final cleaned = base64Str.replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '');
          final rem = cleaned.length % 4;
          final normalised = rem == 0 ? cleaned : cleaned + '=' * (4 - rem);
          final bytes = base64Decode(normalised);
          return Image.memory(bytes, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.person_rounded, color: AppColors.textGray, size: 20));
        } catch (_) {
          return Icon(Icons.person_rounded, color: AppColors.textGray, size: 20);
        }
      }
      return Image.network('${ApiService.baseUrl}$photo', fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.person_rounded, color: AppColors.textGray, size: 20));
    } else if (_currentUser!.avatarType == 'default' && _currentUser!.avatarId != null) {
      final avatarId = _currentUser!.avatarId!;
      final isSvg = avatarId <= 9 || avatarId == 11 || avatarId == 12;
      final path = 'assets/avatar/avatar ($avatarId).${isSvg ? 'svg' : 'png'}';
      if (isSvg) return SvgPicture.asset(path, fit: BoxFit.cover);
      return Image.asset(path, fit: BoxFit.cover);
    }
    return Icon(Icons.person_rounded, color: AppColors.textGray, size: 20);
  }
}

// ── Home content ──────────────────────────────────────────────────────────────
class _HomeContent extends ConsumerWidget {
  const _HomeContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentlyWatched = ref.watch(recentlyWatchedProvider);
    final tvShows = ref.watch(tvShowsProvider);
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return RefreshIndicator(
      color: AppColors.niorRed,
      backgroundColor: AppColors.darkGray,
      onRefresh: () async {
        try {
          final videoManager = VideoManagerService();
          await videoManager.quickScan();
        } catch (e) {
          print('⚠️ HOME: Refresh scan failed - $e');
        }
        ref.invalidate(allVideosProvider);
        ref.invalidate(downloadedVideosProvider);
        ref.invalidate(whatsappVideosProvider);
        ref.invalidate(mostStreamedProvider);
        ref.invalidate(recentlyWatchedProvider);
        ref.invalidate(moviesProvider);
        ref.invalidate(cameraVideosProvider);
        ref.invalidate(tvShowsProvider);
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                recentlyWatched.when(
                  data: (videos) {
                    if (videos.isEmpty) {
                      return Consumer(
                        builder: (context, ref, child) {
                          final downloaded = ref.watch(downloadedVideosProvider);
                          return downloaded.when(
                            data: (vids) => vids.isNotEmpty
                                ? ContinueWatchingCarousel(videos: vids.take(5).toList())
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
                Positioned(
                  top: statusBarHeight, left: 0, right: 0,
                  child: _buildHeader(context),
                ),
              ],
            ),
          ),

          SliverToBoxAdapter(child: const SizedBox(height: 32)),

          SliverToBoxAdapter(
            child: VideoCategoryRow(title: 'Downloaded Videos', provider: downloadedVideosProvider),
          ),
          SliverToBoxAdapter(child: const SizedBox(height: 24)),

          SliverToBoxAdapter(
            child: tvShows.when(
              data: (seriesList) {
                if (seriesList.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('TV SHOWS',
                          style: AppTextStyles.header3.copyWith(
                              color: AppColors.textWhite, fontSize: 20, fontWeight: FontWeight.bold)),
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
                          final episodesAsync = ref.watch(episodesProvider(series.id));
                          return episodesAsync.when(
                            data: (episodes) => SeriesCardWidget(
                              series: series,
                              previewEpisodes: episodes,
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => SeriesDetailScreen(series: series))),
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

          SliverToBoxAdapter(
            child: VideoCategoryRow(title: 'Most Streamed', provider: mostStreamedProvider),
          ),
          SliverToBoxAdapter(child: const SizedBox(height: 24)),

          SliverToBoxAdapter(
            child: VideoCategoryRow(title: 'WhatsApp Videos', provider: whatsappVideosProvider),
          ),
          SliverToBoxAdapter(child: const SizedBox(height: 24)),

          SliverToBoxAdapter(
            child: VideoCategoryRow(title: 'Movies', provider: moviesProvider),
          ),
          SliverToBoxAdapter(child: const SizedBox(height: 24)),

          SliverToBoxAdapter(
            child: VideoCategoryRow(title: 'Camera Videos', provider: cameraVideosProvider),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.black.withOpacity(0.5), Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Image.asset('assets/images/NOIR logo white.png', height: 32, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Text('NOIRSCREEN',
                  style: AppTextStyles.bodyBold.copyWith(
                      color: AppColors.niorRed, fontSize: 13, letterSpacing: 1.2))),
          const Spacer(),
          IconButton(icon: Icon(Icons.cast_rounded, color: AppColors.textWhite, size: 24),
              onPressed: () {}),
          IconButton(icon: Icon(Icons.search_rounded, color: AppColors.textWhite, size: 24),
              onPressed: () {}),
        ],
      ),
    );
  }

  Widget _buildSeriesCardSkeleton() {
    return Container(
      width: 220, height: 320,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(color: AppColors.darkGray, borderRadius: BorderRadius.circular(16)),
    );
  }
}

class _CarouselSkeleton extends StatelessWidget {
  const _CarouselSkeleton();

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.62;
    return Container(
      height: height,
      color: AppColors.darkGray,
      child: Center(child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.niorRed))),
    );
  }
}

class _PlaceholderScreen extends StatelessWidget {
  final String label;
  const _PlaceholderScreen({required this.label});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Center(child: Text(label,
          style: AppTextStyles.header3.copyWith(color: AppColors.ashGray))),
    );
  }
}