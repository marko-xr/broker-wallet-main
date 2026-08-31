// lib/src/Views/Profile/share_app_view.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/images.dart';
import 'package:fluttertoast/fluttertoast.dart';

class ShareAppView extends StatefulWidget {
  const ShareAppView({super.key});

  @override
  State<ShareAppView> createState() => _ShareAppViewState();
}

class _ShareAppViewState extends State<ShareAppView>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final AnimationController _gridController;
  late final AnimationController _pulseController;
  late final Animation<double> _fadeAnimation;
  late final List<AnimationController> _tileControllers;
  late final List<Animation<double>> _tileAnimations;
  late final List<Animation<Offset>> _slideAnimations;
  late final List<Animation<double>> _scaleAnimations;

  bool _isSharing = false;
  String? _shareError;

  @override
  void initState() {
    super.initState();

    // Main fade controller
    _fadeController = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this);
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );

    // Grid entrance controller
    _gridController = AnimationController(
        duration: const Duration(milliseconds: 1200), vsync: this);

    // Pulse effect controller
    _pulseController = AnimationController(
        duration: const Duration(milliseconds: 2000), vsync: this)
      ..repeat(reverse: true);

    // Individual tile controllers (8 tiles)
    _tileControllers = List.generate(
        8,
        (index) => AnimationController(
              duration: Duration(milliseconds: 800 + (index * 100)),
              vsync: this,
            ));

    // Create animations for each tile
    _tileAnimations = _tileControllers
        .map((controller) => CurvedAnimation(
              parent: controller,
              curve: Curves.elasticOut,
            ))
        .toList();

    _slideAnimations = _tileControllers.asMap().entries.map((entry) {
      final index = entry.key;
      final controller = entry.value;
      return Tween<Offset>(
        begin: Offset(0, 0.5 + (index * 0.1)),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutBack,
      ));
    }).toList();

    _scaleAnimations = _tileControllers
        .map((controller) => Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).animate(CurvedAnimation(
              parent: controller,
              curve: Curves.elasticOut,
            )))
        .toList();

    _startAnimations();
  }

  void _startAnimations() async {
    _fadeController.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    _gridController.forward();

    // Stagger tile animations
    for (int i = 0; i < _tileControllers.length; i++) {
      Future.delayed(Duration(milliseconds: 150 * i), () {
        if (mounted) _tileControllers[i].forward();
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _gridController.dispose();
    _pulseController.dispose();
    for (final controller in _tileControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    final items = _shareTargets(loc);

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              const SizedBox(height: 12),
              _buildAppBar(context, loc),
              const SizedBox(height: 32),
              _buildHero(context, loc),
              const SizedBox(height: 40),
              Expanded(child: _buildGrid(items, loc)),
              _buildSystemShareButton(loc),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- UI ----------

  Widget _buildAppBar(BuildContext context, AppLocalizations loc) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Row(
        children: [
          const BackArrowButton(),
          const Spacer(),
          Text(
            loc.translate('shareApp'),
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
                letterSpacing: 0.1),
          ),
          const Spacer(),
          const SizedBox(width: 56),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context, AppLocalizations loc) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.primary,
              colors.primary.withValues(alpha: 0.8),
            ]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: colors.primary.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          // keep a neutral graphic here (optional)
          Image.asset(
            AppImages.mainAppIcon,
            height: 36,
            width: 36,
            errorBuilder: (context, error, stackTrace) => Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.share_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            loc.translate('shareAppWithFriends'),
            style: texts.titleLarge
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            loc.translate('shareAppDescription'),
            style: texts.bodyMedium
                ?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<_ShareTarget> items, AppLocalizations loc) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 16,
          mainAxisSpacing: 20,
          childAspectRatio: 1.0,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _shareTile(items[i], i, loc),
      ),
    );
  }

  Widget _shareTile(_ShareTarget target, int index, AppLocalizations loc) {
    final colors = Theme.of(context).colorScheme;
    final tileAnimation =
        index < _tileAnimations.length ? _tileAnimations[index] : null;
    final slideAnimation =
        index < _slideAnimations.length ? _slideAnimations[index] : null;
    final scaleAnimation =
        index < _scaleAnimations.length ? _scaleAnimations[index] : null;

    return AnimatedBuilder(
      animation: tileAnimation ?? _fadeAnimation,
      builder: (context, child) {
        return SlideTransition(
          position: slideAnimation ?? const AlwaysStoppedAnimation(Offset.zero),
          child: ScaleTransition(
            scale: scaleAnimation ?? const AlwaysStoppedAnimation(1.0),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 400 + (index * 100)),
              curve: Curves.easeOutBack,
              builder: (context, animValue, _) {
                return Transform.translate(
                  offset: Offset(0, (1 - animValue) * 30),
                  child: Opacity(
                    opacity: animValue.clamp(0.0, 1.0),
                    child: _buildTileContent(target, index, colors, loc),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTileContent(_ShareTarget target, int index, ColorScheme colors,
      AppLocalizations loc) {
    return GestureDetector(
      onTap: () => _handleShareTarget(target, loc),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: Column(
          children: [
            // Animated image container with hover effects
            Expanded(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final pulseValue = _pulseController.value;
                  return Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: colors.outline.withValues(alpha: 0.1),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: 0.06),
                          blurRadius: 12 + (pulseValue * 2),
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: target.color
                              .withValues(alpha: 0.1 + (pulseValue * 0.05)),
                          blurRadius: 20 + (pulseValue * 5),
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.8, end: 1.0),
                        duration: Duration(milliseconds: 600 + (index * 100)),
                        curve: Curves.elasticOut,
                        builder: (context, scaleValue, _) {
                          return Transform.scale(
                            scale: scaleValue,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              child: Image.asset(
                                target.asset,
                                height: 48,
                                width: 48,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: target.color.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.share,
                                    color: target.color,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            // Animated text with slide-up effect
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 800 + (index * 150)),
              curve: Curves.easeOutCubic,
              builder: (context, textAnimValue, _) {
                return Transform.translate(
                  offset: Offset(0, (1 - textAnimValue) * 10),
                  child: Opacity(
                    opacity: textAnimValue.clamp(0.0, 1.0),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        target.name,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemShareButton(AppLocalizations loc) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: _isSharing ? null : () => _shareViaSystem(loc),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF009982),
            foregroundColor: Colors.white,
            disabledBackgroundColor: colors.outline.withValues(alpha: 0.3),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            elevation: _isSharing ? 0 : 8,
            shadowColor: const Color(0xFF009982).withValues(alpha: 0.3),
          ),
          icon: _isSharing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.share_rounded, size: 20),
          label: Text(
            _isSharing ? loc.translate('sharing') : loc.translate('share'),
            style: texts.labelLarge?.copyWith(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
          ),
        ),
      ),
    );
  }

  // ---------- Data / Targets ----------

  /// Builds a message-only share text (no store URL yet).
  String _shareMessage(AppLocalizations loc) => loc.translate('shareAppText');

  /// Return share targets that try to open the specific app with the message.
  /// If the scheme isn’t supported, we’ll fall back to system share.
  List<_ShareTarget> _shareTargets(AppLocalizations loc) {
    final msg = Uri.encodeComponent(_shareMessage(loc));

    return [
      _ShareTarget(
        name: 'WhatsApp',
        asset: AppImages.whatsapp,
        color: const Color(0xFF25D366),
        uriBuilder: () => Uri.parse('whatsapp://send?text=$msg'),
      ),
      _ShareTarget(
        name: 'Facebook',
        asset: AppImages.facebookIcon,
        color: const Color(0xFF1877F2),
        // Facebook share dialogs typically require a URL. This will likely fall back.
        uriBuilder: () => Uri.parse(
            'fb://facewebmodal/f?href=https://www.facebook.com/sharer/sharer.php?quote=$msg'),
      ),
      _ShareTarget(
        name: 'Instagram',
        asset: AppImages.googleIcon,
        color: const Color(0xFFE4405F),
        // Instagram doesn’t support text-only deep links; will fall back to system share.
        uriBuilder: () => Uri.parse('instagram://app'),
      ),
      _ShareTarget(
        name: 'X',
        asset: AppImages.mainAppIcon,
        color: const Color(0xFF1DA1F2),
        // X supports text-only via tweet intent
        uriBuilder: () =>
            Uri.parse('https://twitter.com/intent/tweet?text=$msg'),
      ),
      _ShareTarget(
        name: 'Telegram',
        asset: AppImages.whatsapp, // Using WhatsApp icon as fallback
        color: const Color(0xFF24A1DE),
        // tg://msg?text=... is widely supported; tg://share?text=... works too
        uriBuilder: () => Uri.parse('tg://msg?text=$msg'),
      ),
      _ShareTarget(
        name: 'AirDrop',
        asset: AppImages.appleIcons,
        color: const Color(0xFF34C759),
        uriBuilder: () => Uri.parse('sms:?body=$msg'),
      ),
      _ShareTarget(
        name: 'Email',
        asset: AppImages.googleIcon,
        color: const Color(0xFFEA4335),
        uriBuilder: () => Uri.parse(
            'mailto:?subject=${Uri.encodeComponent("Broker Wallet")}&body=$msg'),
      ),
      _ShareTarget(
        name: 'LinkedIn',
        asset: AppImages.mainAppIcon,
        color: const Color(0xFF0084FF),
        // NOTE: LinkedIn generally requires a link for share. We still attempt;
        // if unsupported, system share will take over.
        uriBuilder: () => Uri.parse(
            'https://www.linkedin.com/sharing/share-offsite/?url=$msg'),
      ),
    ];
  }

  // ---------- Actions ----------

  Future<void> _handleShareTarget(
      _ShareTarget target, AppLocalizations loc) async {
    if (_isSharing) return;
    setState(() => _isSharing = true);

    try {
      HapticFeedback.lightImpact();
      final uri = target.uriBuilder();

      // Try the specific app first
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        _toastSuccess(target.name, loc);
        _trackShareEvent(target.name);
      } else {
        // Fallback
        await _shareViaSystem(loc);
        _toastSuccess(loc.translate('systemShare'), loc);
        _trackShareEvent('${target.name}_fallback');
      }
    } catch (_) {
      _shareError = loc.translate('shareError');
      _toastError(loc);
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _shareViaSystem(AppLocalizations loc) async {
    final text = _shareMessage(loc);
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: loc.translate('shareApp'),
      ),
    );
  }

  // ---------- Feedback ----------

  void _toastSuccess(String platform, AppLocalizations loc) {
    Fluttertoast.showToast(
      msg: loc.translate('shareSuccess').replaceAll('{platform}', platform),
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 2,
      backgroundColor: Colors.green,
      textColor: Colors.white,
    );
  }

  void _toastError(AppLocalizations loc) {
    Fluttertoast.showToast(
      msg: _shareError ?? loc.translate('shareError'),
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 3,
      backgroundColor: Colors.red,
      textColor: Colors.white,
    );
  }

  void _trackShareEvent(String platform) {
    // Hook up Firebase Analytics here later
    // FirebaseAnalytics.instance.logEvent(name: 'share_app', parameters: {'platform': platform});
    // ignore: avoid_print
  }
}

// ---------- Model ----------

class _ShareTarget {
  final String name;
  final String asset;
  final Color color;
  final Uri Function() uriBuilder;
  const _ShareTarget(
      {required this.name,
      required this.asset,
      required this.color,
      required this.uriBuilder});
}
