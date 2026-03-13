import 'package:flutter/material.dart';
import 'package:noirscreen/constants/app_text_style.dart';
import 'package:noirscreen/screens/username_setup_screen.dart';
import '../constants/app_colors.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

bool _isLoading = false;

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentIndex = 0;
  int _nextIndex = 1;
  bool _isFading = false;

  final List<String> _images = [
    'assets/images/splash1.jpeg',
    'assets/images/splash2.jpeg',
   // 'assets/images/splash3.jpeg',
    'assets/images/splash4.jpeg',
    //'assets/images/splash5.png',

  ];

  @override
  void initState() {
    super.initState();
    _startCycling();
  }

  void _startCycling() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;

      final next = (_currentIndex + 1) % _images.length;

      setState(() {
        _nextIndex = next;
        _isFading = true; // fade OUT current, revealing next underneath
      });

      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      // Snap current to next silently, reset opacity to 1
      setState(() {
        _currentIndex = next;
        _isFading = false;
      });
    }
  }

  void _handleGetStarted() async {
    setState(() {
      _isLoading = true;
    });

    // Loading simulation
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    // Navigate to the next screen or perform any action after loading
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => UsernameSetupScreen()),
    );
    // Reset loading state after Animation
    if (mounted) {
      setState(() {
        _isLoading = false;
      },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        children: [
          // Next image always sits underneath, ready to be revealed
          Positioned.fill(
            child: Image.asset(_images[_nextIndex], fit: BoxFit.cover),
          ),

          // Current image sits on top and fades OUT to reveal next
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: _isFading ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOut,
              child: Image.asset(_images[_currentIndex], fit: BoxFit.cover),
            ),
          ),

          // Gradient overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.black.withOpacity(0.2),
                    AppColors.black.withOpacity(0.6),
                    AppColors.black.withOpacity(0.85),
                    AppColors.black,
                  ],
                  stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                ),
              ),
            ),
          ),

          // Content at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image(
                      image: const AssetImage('assets/images/NOIR Icon.png'),
                      width: 48,
                      height: 48,
                    ),

                    const SizedBox(height: 20),

                    Text(
                      'NOIRSCREEN',
                      style: AppTextStyles.header1.copyWith(
                        color: AppColors.textWhite,
                        fontSize: 38,
                        letterSpacing: 5,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'Press Play. TOGETHER.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.accentGold,
                        fontSize: 11,
                        letterSpacing: 4,
                      ),
                    ),

                    const SizedBox(height: 40),

                    Text(
                      'Watch movies and anime with friends\nacross the world in perfect sync.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textGray,
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),

                    const SizedBox(height: 50),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleGetStarted,

                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(
                            255,
                            89,
                            29,
                            141,
                          ),
                          foregroundColor: AppColors.textWhite,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          'Get Started',
                          style: AppTextStyles.button.copyWith(
                            fontSize: 18,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
