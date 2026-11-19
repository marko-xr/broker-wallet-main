import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/widgets/disabled_contact_icon.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import 'details_section.dart';
import 'offer_details_style.dart';

/// The Offer Details layout for records with their own fields and actions.
class DetailsPage extends StatelessWidget {
  const DetailsPage({
    super.key,
    required this.title,
    required this.favorite,
    required this.onShare,
    required this.onEdit,
    required this.onDelete,
    required this.deleteLabel,
    required this.onWhatsApp,
    required this.onCall,
    required this.scrollController,
    required this.fade,
    required this.slide,
    required this.contactFade,
    required this.content,
    this.onBack,
    this.media,
  });

  final String title;
  final Widget favorite;
  final VoidCallback onShare;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String deleteLabel;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onCall;
  final ScrollController scrollController;
  final Animation<double> fade;
  final Animation<double> slide;
  final Animation<double> contactFade;
  final WidgetBuilder content;
  final VoidCallback? onBack;
  final WidgetBuilder? media;

  @override
  Widget build(BuildContext context) {
    final scale = OfferDetailsStyle.scale(context);
    return Theme(
      data: OfferDetailsStyle.theme(Theme.of(context), scale: scale),
      child: Builder(builder: (context) {
        final colors = Theme.of(context).colorScheme;
        final loc = AppLocalizations.of(context);
        final mediaBuilder = media;
        final headerEdgeInset = OfferDetailsStyle.headerEdgeInset(scale);
        return Scaffold(
          backgroundColor: colors.surface,
          body: SafeArea(
            top: false,
            bottom: false,
            child: CustomScrollView(
              controller: scrollController,
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  toolbarHeight:
                      OfferDetailsStyle.toolbarHeight(context, scale),
                  backgroundColor: colors.surface,
                  surfaceTintColor: colors.surface,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  centerTitle: true,
                  leadingWidth: kMinInteractiveDimension + headerEdgeInset,
                  title: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  leading: Padding(
                    padding: EdgeInsetsDirectional.only(start: headerEdgeInset),
                    child: DetailsHeaderControl(
                      child: IconButton(
                        tooltip: loc.translate('goBack'),
                        icon: Icon(
                          Directionality.of(context) == TextDirection.rtl
                              ? Icons.chevron_right
                              : Icons.chevron_left,
                          size: 21 * scale,
                          textDirection: TextDirection.ltr,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: onBack ?? () => context.pop(),
                      ),
                    ),
                  ),
                  actions: [
                    DetailsHeaderControl(
                      child: Tooltip(
                        message: loc.translate('favorites'),
                        child: favorite,
                      ),
                    ),
                    SizedBox(width: 4 * scale),
                    DetailsHeaderControl(
                      child: IconButton(
                        tooltip: loc.translate('share'),
                        icon: Icon(Icons.share_outlined, size: 21 * scale),
                        padding: EdgeInsets.zero,
                        onPressed: onShare,
                      ),
                    ),
                    SizedBox(width: 4 * scale),
                    DetailsHeaderControl(
                      child: DetailsActionsMenu(
                        deleteLabel: deleteLabel,
                        onEdit: onEdit,
                        onDelete: onDelete,
                      ),
                    ),
                    SizedBox(width: headerEdgeInset),
                  ],
                ),
                if (mediaBuilder != null)
                  SliverToBoxAdapter(
                    key: const ValueKey('details-media'),
                    child: Padding(
                      padding:
                          EdgeInsets.fromLTRB(12 * scale, 8, 12 * scale, 0),
                      child: Builder(builder: mediaBuilder),
                    ),
                  ),
                SliverToBoxAdapter(
                  key: const ValueKey('details-content'),
                  child: AnimatedBuilder(
                    animation: slide,
                    child: FadeTransition(
                      opacity: fade,
                      child: RepaintBoundary(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                              13 * scale, 14 * scale, 13 * scale, 20),
                          child: Builder(builder: content),
                        ),
                      ),
                    ),
                    builder: (context, child) => Transform.translate(
                      offset: Offset(0, 40 * slide.value),
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: DetailsContactBar(
            fade: contactFade,
            onWhatsApp: onWhatsApp,
            onCall: onCall,
          ),
        );
      }),
    );
  }
}

class DetailsHeaderControl extends StatelessWidget {
  const DetailsHeaderControl({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = 34 * OfferDetailsStyle.scale(context);
    return Center(
      child: SizedBox.square(
        dimension: kMinInteractiveDimension,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surfaceContainerLowest,
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
            IconTheme.merge(
              data: IconThemeData(color: colors.onSurface),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

/// The Call/WhatsApp bar shared by every Details screen, so the two
/// buttons' order, styling, and disabled appearance can only drift out of
/// sync in one place instead of once per screen that duplicates it.
class DetailsContactBar extends StatelessWidget {
  const DetailsContactBar({
    super.key,
    required this.fade,
    required this.onWhatsApp,
    required this.onCall,
  });

  final Animation<double> fade;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final scale = OfferDetailsStyle.scale(context);
    const padding = EdgeInsets.symmetric(horizontal: 10, vertical: 8);
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(13));
    return FadeTransition(
      opacity: fade,
      child: Container(
        decoration: BoxDecoration(color: colors.surface, boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ]),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16 * scale, 10, 16 * scale, 8),
            // Call first, then WhatsApp: same order as the list cards.
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('details-call'),
                  onPressed: onCall,
                  icon: onCall == null
                      ? const DisabledContactIcon.call(size: 18)
                      : const Icon(Icons.phone_rounded, size: 18),
                  label:
                      Text(loc.translate('call'), textAlign: TextAlign.center),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        OfferDetailsStyle.accentText(colors, colors.surface),
                    textStyle: theme.textTheme.labelLarge,
                    minimumSize: const Size(0, kMinInteractiveDimension),
                    padding: padding,
                    side: BorderSide(
                      color: onCall == null
                          ? colors.outlineVariant
                          : colors.primary.withValues(alpha: 0.7),
                      width: 0.8,
                    ),
                    shape: shape,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('details-whatsapp'),
                  onPressed: onWhatsApp,
                  icon: onWhatsApp == null
                      ? DisabledContactIcon.whatsApp(size: 21 * scale)
                      : FaIcon(FontAwesomeIcons.whatsapp, size: 21 * scale),
                  label: Text(loc.translate('whatsapp'),
                      textAlign: TextAlign.center),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: OfferDetailsStyle.primaryButtonForeground,
                    textStyle: theme.textTheme.labelLarge,
                    minimumSize: const Size(0, kMinInteractiveDimension),
                    padding: padding,
                    shape: shape,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
