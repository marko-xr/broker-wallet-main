import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/optimistic_favorites_service.dart';
import '../../services/offline_media_service.dart';
import 'favorite_button.dart';

/// Example usage of OptimizedFavoriteButton in a list/grid item
class OptimizedFavoriteCard extends StatelessWidget {
  final String itemId;
  final String itemType; // 'offers', 'requests', etc.
  final String title;
  final String subtitle;
  final String? imageUrl;
  final VoidCallback? onTap;

  const OptimizedFavoriteCard({
    super.key,
    required this.itemId,
    required this.itemType,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    this.onTap,
  });

  /// Helper method to get appropriate image provider based on URL scheme
  ImageProvider _getImageProvider(String imageUrl) {
    // Use OfflineMediaService for proper URL scheme handling
    return OfflineMediaService.instance.getImageProvider(imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with image/gradient and favorite button
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      gradient: imageUrl == null
                          ? LinearGradient(
                              colors: _getGradientColors(itemType),
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      image: imageUrl != null
                          ? DecorationImage(
                              image: _getImageProvider(imageUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: Stack(
                      children: [
                        // Favorite button with isolated rebuild
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Consumer<OptimisticFavoritesService>(
                            builder: (context, favoritesService, child) {
                              return OptimizedFavoriteButton(
                                isFavorite:
                                    _getFavoriteStatus(favoritesService),
                                isLoading: _getLoadingStatus(favoritesService),
                                onToggle: () =>
                                    _toggleFavorite(favoritesService),
                                size: 20,
                                showBackground: true,
                                padding: const EdgeInsets.all(8),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),

                          // Type badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _getBadgeColor(itemType)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _getTypeDisplayName(itemType),
                              style: textTheme.labelSmall?.copyWith(
                                color: _getBadgeColor(itemType),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _getFavoriteStatus(OptimisticFavoritesService service) {
    switch (itemType) {
      case 'offers':
        return service.isOfferFavorite(itemId);
      case 'requests':
        return service.isRequestFavorite(itemId);
      case 'owners':
        return service.isOwnerFavorite(itemId);
      case 'offices':
        return service.isOfficeFavorite(itemId);
      case 'brokers':
        return service.isBrokerFavorite(itemId);
      case 'watchmen':
        return service.isWatchmenFavorite(itemId);
      default:
        return false;
    }
  }

  bool _getLoadingStatus(OptimisticFavoritesService service) {
    switch (itemType) {
      case 'offers':
        return service.isOfferLoading(itemId);
      case 'requests':
        return service.isRequestLoading(itemId);
      case 'owners':
        return service.isOwnerLoading(itemId);
      case 'offices':
        return service.isOfficeLoading(itemId);
      case 'brokers':
        return service.isBrokerLoading(itemId);
      case 'watchmen':
        return service.isWatchmenLoading(itemId);
      default:
        return false;
    }
  }

  Future<void> _toggleFavorite(OptimisticFavoritesService service) async {
    try {
      switch (itemType) {
        case 'offers':
          await service.toggleOfferFavorite(itemId);
          break;
        case 'requests':
          await service.toggleRequestFavorite(itemId);
          break;
        case 'owners':
          await service.toggleOwnerFavorite(itemId);
          break;
        case 'offices':
          await service.toggleOfficeFavorite(itemId);
          break;
        case 'brokers':
          await service.toggleBrokerFavorite(itemId);
          break;
        case 'watchmen':
          await service.toggleWatchmenFavorite(itemId);
          break;
      }
    } catch (e) {
      // Error handling is done by the service
    }
  }

  List<Color> _getGradientColors(String type) {
    switch (type) {
      case 'requests':
        return [const Color(0xFF6B46C1), const Color(0xFF8B5CF6)];
      case 'offers':
        return [const Color(0xFF059669), const Color(0xFF10B981)];
      case 'owners':
        return [const Color(0xFFEA580C), const Color(0xFFF97316)];
      case 'offices':
        return [const Color(0xFF2563EB), const Color(0xFF3B82F6)];
      case 'brokers':
        return [const Color(0xFF4F46E5), const Color(0xFF6D28D9)];
      case 'watchmen':
        return [const Color(0xFFEBE835), const Color(0xFFEAB308)];
      default:
        return [const Color(0xFF334155), const Color(0xFF64748B)];
    }
  }

  Color _getBadgeColor(String type) {
    switch (type) {
      case 'requests':
        return const Color(0xFF6B46C1);
      case 'offers':
        return const Color(0xFF059669);
      case 'owners':
        return const Color(0xFFEA580C);
      case 'offices':
        return const Color(0xFF2563EB);
      case 'brokers':
        return const Color(0xFF4F46E5);
      case 'watchmen':
        return const Color(0xFFEBE835);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _getTypeDisplayName(String type) {
    switch (type) {
      case 'offers':
        return 'Offer';
      case 'requests':
        return 'Request';
      case 'owners':
        return 'Owner';
      case 'offices':
        return 'Office';
      case 'brokers':
        return 'Broker';
      case 'watchmen':
        return 'Watchmen';
      default:
        return 'Item';
    }
  }
}
