import 'package:flutter/material.dart';
import 'package:noirscreen/constants/app_text_style.dart';
import 'package:noirscreen/screens/onboarding_screen.dart';
import 'dart:math' as math;
import '../constants/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _barWipeController;
  late Animation<double> _barWipeAnimation;

  late AnimationController _logoController;
  late Animation<double> _logoOpacity;
  late Animation<double> _logoScale;

  late AnimationController _lineController;
  late Animation<double> _lineWidth;

  late AnimationController _textController;
  late Animation<double> _textReveal;
  late Animation<double> _textOpacity;

  late AnimationController _taglineController;
  late Animation<double> _taglineOpacity;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startSequence();
  }

  void _setupAnimations() {
    _barWipeController = AnimationController(
      duration: const Duration(milliseconds: 850),
      vsync: this,
    );
    _barWipeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _barWipeController, curve: Curves.easeInOutCubic),
    );

    _logoController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _logoOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _logoController, curve: Curves.easeOut));
    _logoScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutCubic),
    );

    _lineController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _lineWidth = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _lineController, curve: Curves.easeOutCubic),
    );

    _textController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _textReveal = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeInOutCubic),
    );
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
      ),
    );

    _taglineController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _taglineController, curve: Curves.easeIn),
    );
  }

  bool _showLoading = false;

  void _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 400));

    _barWipeController.forward();
    await Future.delayed(const Duration(milliseconds: 500));

    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 400));

    _lineController.forward();
    await Future.delayed(const Duration(milliseconds: 300));

    _textController.forward();
    await Future.delayed(const Duration(milliseconds: 700));

    _taglineController.forward();
    await Future.delayed(const Duration(milliseconds: 2000));

    if (mounted) {
      setState(() {
        _showLoading = true;
      });
    }
    // loading for 5 sec than navigate
    await Future.delayed(const Duration(microseconds: 5000));
    if (mounted) {
      // Navigate to the next screen or perform any action after the splash screen
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(builder:(context) => const OnboardingScreen(),
        ),
      );
    }
  }

  @override
  void dispose() {
    _barWipeController.dispose();
    _logoController.dispose();
    _lineController.dispose();
    _textController.dispose();
    _taglineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),

          AnimatedBuilder(
            animation: _barWipeAnimation,
            builder: (context, _) {
              final progress = _barWipeAnimation.value;
              if (progress == 0) return const SizedBox.shrink();
              return Positioned(
                top: screenHeight * progress - 2,
                left: 0,
                right: 0,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        AppColors.niorRed,
                        AppColors.niorRed,
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.2, 0.8, 1.0],
                    ),
                  ),
                ),
              );
            },
          ),

          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Your logo image ──────────────────────────────────────
                AnimatedBuilder(
                  animation: _logoController,
                  builder: (context, _) {
                    return Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: Image.asset(
                          'assets/images/Asset 1.png',
                          width: 72,
                          height: 72,
                          fit: BoxFit.contain,
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 28),

                AnimatedBuilder(
                  animation: _lineController,
                  builder: (context, _) {
                    return SizedBox(
                      width: 200,
                      height: 1.5,
                      child: FractionallySizedBox(
                        widthFactor: _lineWidth.value,
                        alignment: Alignment.center,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.niorRed.withOpacity(0.3),
                                AppColors.niorRed,
                                AppColors.niorRed.withOpacity(0.3),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 20),

                AnimatedBuilder(
                  animation: _textController,
                  builder: (context, _) {
                    return Opacity(
                      opacity: _textOpacity.value,
                      child: ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: _textReveal.value,
                          child: Text(
                            'NOIRSCREEN',
                            style: AppTextStyles.header1.copyWith(
                              color: const Color.fromARGB(255, 138, 119, 146),
                              fontSize: 30,
                              letterSpacing: 0.3,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 12),

                AnimatedBuilder(
                  animation: _taglineController,
                  builder: (context, _) {
                    return Opacity(
                      opacity: _taglineOpacity.value,
                      child: Text(
                        'Press Play. TOGETHER.',
                        style: AppTextStyles.header1.copyWith(
                          color: AppColors.accentGold,
                          fontSize: 11,
                          letterSpacing: 5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          Positioned(top: 40, left: 32, child: _CornerBracket(flip: false)),

          Positioned(bottom: 40, right: 32, child: _CornerBracket(flip: true)),
        
        // Loading  Spinner bottom
        if (_showLoading)
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(AppColors.niorRed),
                ),
              ),
            ),
            ),
        ],
      ),
    );
  }
}

// ── Subtle grid background ────────────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.025)
      ..strokeWidth = 0.5;

    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Corner bracket decoration ─────────────────────────────────────────────────
class _CornerBracket extends StatelessWidget {
  final bool flip;
  const _CornerBracket({required this.flip});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: flip ? math.pi : 0,
      child: SizedBox(
        width: 24,
        height: 24,
        child: CustomPaint(painter: _BracketPainter()),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color.fromARGB(255, 82, 67, 68).withOpacity(0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    canvas.drawLine(Offset(0, size.height), const Offset(0, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
