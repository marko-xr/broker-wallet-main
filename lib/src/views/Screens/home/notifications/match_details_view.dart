import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/request_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Screen showing match details between a request and an offer
/// Displays both items side-by-side or stacked with comparison highlights
class MatchDetailsView extends StatefulWidget {
  const MatchDetailsView({
    super.key,
    required this.requestId,
    required this.offerId,
    this.matchScore,
  });

  final String requestId;
  final String offerId;
  final double? matchScore;

  @override
  State<MatchDetailsView> createState() => _MatchDetailsViewState();
}

class _MatchDetailsViewState extends State<MatchDetailsView> {
  final OfferService _offerService = OfferService();
  final RequestService _requestService = RequestService();

  bool _isLoading = true;
  RequestModel? _request;
  OfferModel? _offer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load both request and offer in parallel
      final results = await Future.wait([
        _requestService.getRequest(widget.requestId),
        _offerService.getOffer(widget.offerId),
      ]);

      setState(() {
        _request = results[0] as RequestModel?;
        _offer = results[1] as OfferModel?;
        _isLoading = false;

        if (_request == null || _offer == null) {
          _error = 'Could not load match details';
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Error loading data: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.translate('matchDetails')),
        actions: [
          if (widget.matchScore != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                avatar: Icon(Icons.verified, color: colors.primary, size: 18),
                label: Text(
                  '${(widget.matchScore! * 100).toStringAsFixed(0)}% ${localization.translate('match')}',
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: colors.primary.withValues(alpha: 0.1),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState(localization)
              : _buildContent(context, localization),
    );
  }

  Widget _buildErrorState(AppLocalizations localization) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            _error ?? localization.translate('errorLoadingData'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: _loadData,
            child: Text(localization.translate('retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, AppLocalizations localization) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Match banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colors.primary.withValues(alpha: 0.1),
                    colors.secondary.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.handshake, color: colors.primary, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          localization.translate('matchFoundTitle'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          localization.translate('matchFoundSubtitle'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Your Request section
            _buildSectionHeader(
              context,
              icon: Icons.search,
              title: localization.translate('yourRequest'),
              color: colors.tertiary,
            ),
            const SizedBox(height: 12),
            _buildRequestCard(context, localization),

            const SizedBox(height: 24),

            // Matching Offer section
            _buildSectionHeader(
              context,
              icon: Icons.home_work,
              title: localization.translate('matchingOffer'),
              color: colors.primary,
            ),
            const SizedBox(height: 12),
            _buildOfferCard(context, localization),

            const SizedBox(height: 32),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _viewRequestDetails(context),
                    icon: const Icon(Icons.search),
                    label: Text(localization.translate('viewRequest')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _viewOfferDetails(context),
                    icon: const Icon(Icons.home_work),
                    label: Text(localization.translate('viewOffer')),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Contact owner button
            if (_offer != null)
              FilledButton.tonalIcon(
                onPressed: () => _contactOwner(context),
                icon: const Icon(Icons.phone),
                label: Text(localization.translate('contactOwner')),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _buildRequestCard(
      BuildContext context, AppLocalizations localization) {
    if (_request == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(localization.translate('requestNotFound')),
        ),
      );
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final request = _request!;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Request type badge
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: request.requestType == 'rent'
                        ? Colors.blue.withValues(alpha: 0.1)
                        : Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    request.requestType == 'rent'
                        ? localization.translate('forRent')
                        : localization.translate('forSale'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: request.requestType == 'rent'
                          ? Colors.blue
                          : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(request.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Property type & location
            Text(
              request.propertyType ?? localization.translate('anyPropertyType'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (request.location.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.location_on,
                      size: 16, color: colors.onSurface.withValues(alpha: 0.6)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      request.location,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),

            // Budget & requirements
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (request.minPrice.isNotEmpty || request.maxPrice.isNotEmpty)
                  _buildInfoChip(
                    Icons.attach_money,
                    _formatPriceRange(request.minPrice, request.maxPrice),
                    colors,
                  ),
                _buildInfoChip(
                  Icons.bed,
                  '${request.rooms} ${localization.translate('rooms')}',
                  colors,
                ),
                _buildInfoChip(
                  Icons.bathtub,
                  '${request.bathrooms} ${localization.translate('bathrooms')}',
                  colors,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfferCard(BuildContext context, AppLocalizations localization) {
    if (_offer == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(localization.translate('offerNotFound')),
        ),
      );
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final offer = _offer!;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image if available
          if (offer.mediaUrls.isNotEmpty)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  offer.mediaUrls.first,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: colors.surfaceContainerHighest,
                    child: Icon(Icons.home, size: 48, color: colors.outline),
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Offer type badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: offer.offerType == 'rent'
                            ? Colors.blue.withValues(alpha: 0.1)
                            : Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        offer.offerType == 'rent'
                            ? localization.translate('forRent')
                            : localization.translate('forSale'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: offer.offerType == 'rent'
                              ? Colors.blue
                              : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatDate(offer.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Property type
                Text(
                  offer.propertyType ?? localization.translate('property'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (offer.location.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on,
                          size: 16,
                          color: colors.onSurface.withValues(alpha: 0.6)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          offer.location,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 12),

                // Price range
                if (offer.minPrice.isNotEmpty || offer.maxPrice.isNotEmpty)
                  Text(
                    _formatPriceRange(offer.minPrice, offer.maxPrice),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.primary,
                    ),
                  ),

                const SizedBox(height: 12),

                // Details
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildInfoChip(
                      Icons.bed,
                      '${offer.rooms} ${localization.translate('rooms')}',
                      colors,
                    ),
                    _buildInfoChip(
                      Icons.bathtub,
                      '${offer.bathrooms} ${localization.translate('bathrooms')}',
                      colors,
                    ),
                    if (offer.squareFootage.isNotEmpty)
                      _buildInfoChip(
                        Icons.square_foot,
                        '${offer.squareFootage} sqft',
                        colors,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.onSurface.withValues(alpha: 0.7)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colors.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return DateFormat.yMMMd().format(date);
  }

  String _formatPriceRange(String minPrice, String maxPrice) {
    if (minPrice.isNotEmpty && maxPrice.isNotEmpty) {
      return 'AED $minPrice - $maxPrice';
    }
    if (minPrice.isNotEmpty) {
      return 'AED $minPrice+';
    }
    if (maxPrice.isNotEmpty) {
      return 'Up to AED $maxPrice';
    }
    return 'Any budget';
  }

  void _viewRequestDetails(BuildContext context) {
    if (_request != null) {
      context.push('/requested-details', extra: _request);
    }
  }

  void _viewOfferDetails(BuildContext context) {
    if (_offer != null) {
      context.push('/offers-details', extra: _offer);
    }
  }

  void _contactOwner(BuildContext context) {
    if (_offer != null && _offer!.phoneNumber.isNotEmpty) {
      // Show contact options dialog
      showModalBottomSheet(
        context: context,
        builder: (context) => _ContactOptionsSheet(
          phoneNumber: _offer!.phoneNumber,
        ),
      );
    }
  }
}

class _ContactOptionsSheet extends StatelessWidget {
  const _ContactOptionsSheet({
    required this.phoneNumber,
  });

  final String phoneNumber;

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              localization.translate('contactOwner'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              phoneNumber,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ContactOption(
                  icon: Icons.phone,
                  label: localization.translate('call'),
                  onTap: () {
                    Navigator.pop(context);
                    // Launch phone dialer
                    // launchUrl(Uri.parse('tel:$phoneNumber'));
                  },
                ),
                _ContactOption(
                  icon: Icons.chat,
                  label: 'WhatsApp',
                  onTap: () {
                    Navigator.pop(context);
                    // Launch WhatsApp
                    // launchUrl(Uri.parse('https://wa.me/$phoneNumber'));
                  },
                ),
                _ContactOption(
                  icon: Icons.message,
                  label: 'SMS',
                  onTap: () {
                    Navigator.pop(context);
                    // Launch SMS
                    // launchUrl(Uri.parse('sms:$phoneNumber'));
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _ContactOption extends StatelessWidget {
  const _ContactOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: colors.primary),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
