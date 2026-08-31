import 'package:flutter/material.dart';
import 'package:broker_wallet/src/common/utils/images.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late AnimationController _pulseController;

  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Scale animation for logo entrance
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // Fade animation for logo
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Pulse animation for logo
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _startAnimations();
  }

  void _startAnimations() async {
    // Check if widget is still mounted before each step
    if (!mounted) return;

    // Start fade and scale animations
    _fadeController.forward();
    await Future.delayed(const Duration(milliseconds: 200));

    if (!mounted) return;
    _scaleController.forward();

    // Start pulse animation after scale completes
    await Future.delayed(const Duration(milliseconds: 800));

    // Check if widget is still mounted and controller is not disposed
    if (!mounted || _pulseController.isAnimating) return;

    try {
      _pulseController.repeat(reverse: true);
    } catch (e) {
      // Handle the case where controller is already disposed
      debugPrint('Animation controller already disposed: $e');
    }

    // Navigate after 2 more seconds (total 3 seconds)
    await Future.delayed(const Duration(milliseconds: 2000));

    // Check if widget is still mounted before navigation
    // Note: Don't navigate from splash - let AuthWrapper handle navigation
    // if (mounted) {
    //   context.go('/welcome');
    // }
  }

  @override
  void dispose() {
    // Stop all animations before disposing
    try {
      if (_scaleController.isAnimating) {
        _scaleController.stop();
      }
      if (_fadeController.isAnimating) {
        _fadeController.stop();
      }
      if (_pulseController.isAnimating) {
        _pulseController.stop();
      }
    } catch (e) {
      debugPrint('Error stopping animations: $e');
    }

    // Dispose controllers
    _scaleController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF20A28D),
              Color(0xFF217D6A),
              Color(0xFF206054),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated logo
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.3),
                                    blurRadius: 30,
                                    spreadRadius: 10,
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                AppImages.appLogo,
                                height: 160,
                                width: 160,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // App name with fade animation
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Builder(
                      builder: (context) {
                        return ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Colors.white, Colors.white70],
                          ).createShader(bounds),
                          child: Text(
                            AppLocalizations.of(context).translate('appName'),
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 2.0,
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Tagline
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Builder(
                      builder: (context) {
                        return Text(
                          AppLocalizations.of(context).translate('appTagline'),
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w400,
                            letterSpacing: 1.0,
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 60),

                  // Loading indicator
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SizedBox(
                      width: 80,
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white.withValues(alpha: 0.3),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                        minHeight: 3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Version info at bottom
            Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Builder(
                  builder: (context) {
                    return Text(
                      AppLocalizations.of(context).translate('appVersion'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
