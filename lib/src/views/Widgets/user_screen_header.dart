import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/current_user_avatar.dart';
import 'package:broker_wallet/src/views/Widgets/notification_icon.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// The header of the three main tabs (Home, Search, Favorites): the user's
/// avatar, "Hi <name>", a line that says what the screen is, and the bell.
///
/// It is one widget so the three cannot drift apart: the same avatar size, name
/// style, gap between the two lines, subtitle size and colour, single-line
/// overflow and tap target. A screen passes only its own [subtitle].
///
/// It subscribes to [AuthViewModel] itself, so a name or photo change shows at
/// once on every tab (the tabs are kept alive side by side) without rebuilding
/// the screen around it.
class UserScreenHeader extends StatelessWidget {
  const UserScreenHeader({super.key, required this.subtitle});

  /// What this screen is, in a few words (not a second greeting).
  final String subtitle;

  /// The avatar and the bell are both this tall.
  static const double avatarSize = 48;

  /// The room between the avatar and the text.
  static const double avatarGap = 12;

  /// The room between the name and the subtitle.
  static const double lineGap = 2;

  /// How much of the text colour the subtitle keeps.
  static const double subtitleOpacity = 0.6;

  @override
  Widget build(BuildContext context) {
    final authVM = Provider.of<AuthViewModel>(context);
    final localization = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final resolvedName = authVM.displayName.trim();
    final userName = resolvedName.isNotEmpty
        ? resolvedName
        : localization.translate('favoritesGuestUser');

    return Row(
      children: [
        CurrentUserAvatar(
          size: avatarSize,
          onTap: () => context.push('/edit-profile'),
        ),
        const SizedBox(width: avatarGap),
        Expanded(
          child: GestureDetector(
            onTap: () => context.push('/edit-profile'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    '${localization.translate('hiGreeting')} $userName',
                    key: ValueKey(userName),
                    style: textTheme.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: lineGap),
                Text(
                  subtitle,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface.withValues(alpha: subtitleOpacity),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        const NotificationIcon(),
      ],
    );
  }
}
