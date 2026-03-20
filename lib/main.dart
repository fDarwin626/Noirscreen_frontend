import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_links/app_links.dart';
import 'package:noirscreen/constants/app_colors.dart';
import 'package:noirscreen/screens/splash_screen.dart';
import 'package:noirscreen/screens/home_screen.dart';
import 'package:noirscreen/screens/room_watch_screen.dart';
import 'package:noirscreen/services/rooms_service.dart';
import 'package:noirscreen/services/auth_service.dart';
import 'package:noirscreen/services/api_services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(
    const ProviderScope(
      child: NoirScreenApp(),
    ),
  );
}

class NoirScreenApp extends StatefulWidget {
  const NoirScreenApp({super.key});

  @override
  State<NoirScreenApp> createState() => _NoirScreenAppState();
}

class _NoirScreenAppState extends State<NoirScreenApp> {
  final _appLinks = AppLinks();
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  void _initDeepLinks() {
    // Listen for links while app is already open
    _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }

  Future<void> _handleDeepLink(Uri uri) async {
    // Only handle noirscreen://room/ROOM_ID
    if (uri.scheme != 'noirscreen' || uri.host != 'room') return;

    final roomId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (roomId == null || roomId.isEmpty) return;

    print('🔗 DEEP LINK: Received room link for $roomId');

    try {
      final roomsService = RoomsService();
      final authService = AuthService();
      final apiService = ApiService();

      // Get current user
      final userId = await authService.getUserId();
      if (userId == null) {
        print('❌ DEEP LINK: No user logged in');
        return;
      }
      final user = await apiService.getUser(userId);
      if (user == null) {
        print('❌ DEEP LINK: Could not load user');
        return;
      }

      // Fetch room details from backend
      final link = 'noirscreen://room/$roomId';
      final room = await roomsService.joinViaLink(link);
      if (room == null) {
        print('❌ DEEP LINK: Room not found or expired');
        return;
      }

      print('✅ DEEP LINK: Joining room ${room.videoTitle}');

      // Navigate to watch screen as viewer
      // Never owner from a link — owner always joins from their own room card
      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => RoomWatchScreen(
            room: room,
            currentUser: user,
            isOwner: false,
            localFilePath: null,
            hlsStreamUrl:
                '${ApiService.baseUrl}/api/rooms/${room.roomId}/stream.m3u8',
          ),
        ),
      );
    } catch (e) {
      print('❌ DEEP LINK: Error handling link - $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NoirScreen',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.backgroundDark,
        primaryColor: AppColors.niorRed,
        colorScheme: ColorScheme.dark(
          primary: AppColors.niorRed,
          secondary: AppColors.ashGray,
          surface: AppColors.darkGray,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}