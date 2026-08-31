import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/uae_links_model.dart';

class UAELinksView extends StatefulWidget {
  const UAELinksView({Key? key}) : super(key: key);

  @override
  State<UAELinksView> createState() => _UAELinksViewState();
}

class _UAELinksViewState extends State<UAELinksView>
    with SingleTickerProviderStateMixin {
  List<UAELinkCategory> _allCategories = [];
  List<UAELinkCategory> _filteredCategories = [];
  final TextEditingController _searchController = TextEditingController();
  late AnimationController _animationController;
  String _selectedEmirate = ''; // Will be initialized in build

  List<String> _getEmiratesList(AppLocalizations localization) {
    return [
      localization.translate('all'),
      localization.translate('uaeEssentials'),
      localization.translate('dubai'),
      localization.translate('abuDhabi'),
      localization.translate('sharjah'),
      localization.translate('ajman'),
      localization.translate('rasAlKhaimah'),
      localization.translate('ummAlQuwain'),
      localization.translate('fujairah'),
    ];
  }

  @override
  void initState() {
    super.initState();
    // Initialize with empty categories first, will be populated in build
    _filteredCategories = [];
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _filterLinks(AppLocalizations localization) {
    if (_allCategories.isEmpty) {
      _allCategories = UAELinksData.getCategories(localization.translate);
    }

    setState(() {
      String query = _searchController.text.toLowerCase();
      String selectedEmirateTranslated = _selectedEmirate.toLowerCase();

      _filteredCategories = _allCategories.where((category) {
        // Filter by emirate
        if (_selectedEmirate != localization.translate('all') &&
            !category.title.toLowerCase().contains(selectedEmirateTranslated)) {
          return false;
        }

        // Filter by search query
        if (query.isEmpty) return true;

        bool categoryMatches = category.title.toLowerCase().contains(query);
        bool hasMatchingItems = category.items.any((item) =>
            item.label.toLowerCase().contains(query) ||
            (item.description?.toLowerCase().contains(query) ?? false));

        return categoryMatches || hasMatchingItems;
      }).map((category) {
        // If searching, filter items within categories
        if (query.isEmpty) return category;

        var filteredItems = category.items
            .where((item) =>
                item.label.toLowerCase().contains(query) ||
                (item.description?.toLowerCase().contains(query) ?? false))
            .toList();

        return UAELinkCategory(
          title: category.title,
          items: filteredItems.isNotEmpty ? filteredItems : category.items,
        );
      }).toList();
    });
  }

  Future<void> _launchURL(String url) async {
    final localization = AppLocalizations.of(context);
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showErrorSnackBar(localization.translate('unableToOpenLink'));
      }
    } catch (e) {
      _showErrorSnackBar(
          '${localization.translate('errorOpeningLink')}: ${e.toString()}');
    }
  }

  void _copyToClipboard(String url) {
    final localization = AppLocalizations.of(context);
    Clipboard.setData(ClipboardData(text: url));
    _showSuccessSnackBar(localization.translate('linkCopiedToClipboard'));
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  PreferredSizeWidget _buildAdvancedAppBar(
      AppLocalizations localization, ColorScheme colors) {
    return AppBar(
      leading: const BackArrowButton(
        iconColor: Colors.white, // Set to white to match the blue gradient
        backgroundColor: Colors
            .transparent, // Make background transparent since we have gradient
        showBackground: false, // Disable the default background circle
      ),
      title: Column(
        children: [
          Text(
            localization.translate('uaeLinks'),
            style: AppTextStyles.appBarTitle.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          Text(
            localization.translate('govPortalsAndServices'),
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF1976D2).withValues(alpha: 0.9),
              const Color(0xFF0D47A1).withValues(alpha: 0.7),
              Colors.transparent,
            ],
          ),
        ),
      ),
      toolbarHeight: 80,
    );
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    // Initialize categories if not already done
    if (_allCategories.isEmpty) {
      _allCategories = UAELinksData.getCategories(localization.translate);
      if (_filteredCategories.isEmpty) {
        _filteredCategories = _allCategories;
      }
    }

    // Set default selected emirate to localized 'All' if not set
    if (_selectedEmirate.isEmpty) {
      _selectedEmirate = localization.translate('all');
    }

    return Scaffold(
      backgroundColor: colors.surface,
      extendBodyBehindAppBar: true,
      appBar: _buildAdvancedAppBar(localization, colors),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.surface,
              colors.surface.withValues(alpha: 0.95),
            ],
          ),
        ),
        child: Column(
          children: [
            // Header space for transparent app bar
            const SizedBox(height: 120),
            // Header section
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1976D2), Color(0xFF0D47A1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1976D2).withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          localization.translate('essentialLinks'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          localization.translate('quickAccessToGovPortals'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.link_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),

            // Search and filter section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // Search bar
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => _filterLinks(localization),
                    decoration: InputDecoration(
                      hintText: localization.translate('searchLinks'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _filterLinks(localization);
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor:
                          colors.surfaceContainerHighest.withValues(alpha: 0.5),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Emirate filter chips
                  SizedBox(
                    height: 40,
                    child: Builder(
                      builder: (context) {
                        final emiratesList = _getEmiratesList(localization);
                        return ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: emiratesList.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final emirate = emiratesList[index];
                            final isSelected = _selectedEmirate == emirate;

                            return FilterChip(
                              label: Text(emirate),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  _selectedEmirate = emirate;
                                  _filterLinks(localization);
                                });
                              },
                              backgroundColor: colors.surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                              selectedColor: const Color(0xFF1976D2)
                                  .withValues(alpha: 0.2),
                              checkmarkColor: const Color(0xFF1976D2),
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? const Color(0xFF1976D2)
                                    : colors.onSurface,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Links list
            Expanded(
              child: _filteredCategories.isEmpty
                  ? _buildEmptyState(colors, localization)
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _filteredCategories.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final category = _filteredCategories[index];
                        return AnimatedBuilder(
                          animation: _animationController,
                          builder: (context, child) {
                            final animationValue = Curves.easeOutBack
                                .transform(
                                  (_animationController.value - (index * 0.1))
                                      .clamp(0.0, 1.0),
                                )
                                .clamp(0.0, 1.0);
                            return Transform.translate(
                              offset: Offset(0, 30 * (1 - animationValue)),
                              child: Opacity(
                                opacity: animationValue,
                                child: _buildCategoryCard(
                                    category, colors, localization),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colors, AppLocalizations localization) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 64,
            color: colors.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            localization.translate('noLinksFound'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            localization.translate('tryDifferentSearch'),
            style: TextStyle(
              fontSize: 14,
              color: colors.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(UAELinkCategory category, ColorScheme colors,
      AppLocalizations localization) {
    return Card(
      elevation: 8,
      shadowColor: colors.primary.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.surface,
              colors.surface.withValues(alpha: 0.8),
            ],
          ),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          childrenPadding: const EdgeInsets.only(bottom: 16),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1976D2).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getCategoryIcon(category.title),
              color: const Color(0xFF1976D2),
              size: 24,
            ),
          ),
          title: Text(
            category.title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          subtitle: Text(
            '${category.items.length} ${localization.translate('links')}',
            style: TextStyle(
              fontSize: 12,
              color: colors.onSurface.withValues(alpha: 0.6),
            ),
          ),
          children: category.items
              .map((item) => _buildLinkItem(item, colors, localization))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildLinkItem(
      UAELinkItem item, ColorScheme colors, AppLocalizations localization) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.outline.withValues(alpha: 0.1),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1976D2).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.language_rounded,
            color: Color(0xFF1976D2),
            size: 20,
          ),
        ),
        title: Text(
          item.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
        ),
        subtitle: item.description != null
            ? Text(
                item.description!,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.onSurface.withValues(alpha: 0.7),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 20),
              onPressed: () => _copyToClipboard(item.url),
              tooltip: localization.translate('copyLink'),
              style: IconButton.styleFrom(
                backgroundColor:
                    colors.surfaceContainerHighest.withValues(alpha: 0.5),
                foregroundColor: colors.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              onPressed: () => _launchURL(item.url),
              tooltip: localization.translate('openLink'),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2).withValues(alpha: 0.1),
                foregroundColor: const Color(0xFF1976D2),
              ),
            ),
          ],
        ),
        onTap: () => _launchURL(item.url),
      ),
    );
  }

  IconData _getCategoryIcon(String categoryTitle) {
    switch (categoryTitle.toLowerCase()) {
      case 'uae essentials':
        return Icons.verified_user_rounded;
      case 'dubai (dld / rera)':
        return Icons.location_city_rounded;
      case 'abu dhabi':
        return Icons.business_rounded;
      case 'sharjah':
        return Icons.apartment_rounded;
      case 'ajman':
        return Icons.domain_rounded;
      case 'ras al khaimah':
        return Icons.villa_rounded;
      case 'umm al quwain':
        return Icons.home_work_rounded;
      case 'fujairah':
        return Icons.holiday_village_rounded;
      default:
        return Icons.link_rounded;
    }
  }
}
