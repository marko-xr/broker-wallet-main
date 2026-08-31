/// Quota-Aware Widget Example
///
/// This demonstrates how to use the QuotaService in a Flutter widget
/// with optimistic UI updates and proper error handling.

import 'package:broker_wallet/src/constants/constants.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:uuid/uuid.dart';

import '../services/quota_service.dart';

/// Model for tracking items with optimistic UI state
class ItemEntry {
  const ItemEntry({
    required this.id,
    required this.data,
    required this.isSynced,
  });

  final String id;
  final Map<String, dynamic> data;
  final bool isSynced;

  ItemEntry copyWith({
    String? id,
    Map<String, dynamic>? data,
    bool? isSynced,
  }) {
    return ItemEntry(
      id: id ?? this.id,
      data: data ?? this.data,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}

/// Example widget showing quota-aware section with add functionality
class QuotaAwareSectionPage extends StatefulWidget {
  const QuotaAwareSectionPage({
    super.key,
    required this.section,
    required this.sectionTitle,
    required this.uid,
  });

  final String section;
  final String sectionTitle;
  final String uid;

  @override
  State<QuotaAwareSectionPage> createState() => _QuotaAwareSectionPageState();
}

class _QuotaAwareSectionPageState extends State<QuotaAwareSectionPage> {
  final QuotaService _quotaService = QuotaService();
  final List<ItemEntry> _items = <ItemEntry>[];
  bool _isSaving = false;

  /// Add item with optimistic UI and server validation
  Future<void> _addItem(Map<String, dynamic> itemData) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    // Generate idempotency token
    final optimisticId = const Uuid().v4();

    // Optimistically add to UI
    final optimisticEntry = ItemEntry(
      id: optimisticId,
      data: {
        ...itemData,
        'title': itemData['title'] ?? 'New Item',
        'status': 'Pending sync…',
      },
      isSynced: false,
    );

    setState(() => _items.insert(0, optimisticEntry));

    try {
      // Call server with quota enforcement
      final result = await _quotaService.addItem(
        section: widget.section,
        payload: itemData,
        idempotencyToken: optimisticId,
      );

      // Update with actual server ID
      setState(() {
        final index = _items.indexWhere((entry) => entry.id == optimisticId);
        if (index >= 0) {
          _items[index] = optimisticEntry.copyWith(
            id: result.itemId,
            isSynced: true,
            data: {
              ...optimisticEntry.data,
              'status': 'Synced',
              'remainingQuota': result.remainingQuota,
            },
          );
        }
      });

      // Show success
      if (mounted) {
        _showToast(
          'Item added successfully! ${result.remainingQuota != null ? "${result.remainingQuota} slots remaining" : ""}',
          isError: false,
        );
      }
    } on QuotaExceededException catch (error) {
      // Remove optimistic entry
      setState(() {
        _items.removeWhere((entry) => entry.id == optimisticId);
      });

      // Show upgrade dialog
      if (mounted) {
        _showUpgradeDialog(error);
      }
    } on AuthRequiredException catch (error) {
      setState(() => _items.removeWhere((entry) => entry.id == optimisticId));
      _showToast(error.message, isError: true);
    } on Exception catch (error) {
      setState(() => _items.removeWhere((entry) => entry.id == optimisticId));
      _showToast(error.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Show upgrade dialog when quota is exceeded
  void _showUpgradeDialog(QuotaExceededException error) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upgrade to Premium'),
        content: Text(
          '${error.message}\n\n'
          'Unlock unlimited items and premium features:\n\n'
          '• Unlimited items in all sections\n'
          '• Priority support\n'
          '• Advanced analytics\n'
          '• Export capabilities\n\n'
          'Plans:\n'
          '• AED 120/year (Save 33%)\n'
          '• AED 15/month',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Navigate to subscription/payment page
              _showToast('Payment flow not yet implemented', isError: false);
            },
            child: Text(
              'See Plans',
              style: AppTextStyles.buttonText.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showToast(String message, {required bool isError}) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: isError ? Colors.red : Colors.green,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sectionTitle),
        actions: [
          // Show remaining quota
          StreamBuilder<Map<String, int>>(
            stream: _quotaService.countsStream(widget.uid),
            builder: (context, snapshot) {
              final counts = snapshot.data ?? <String, int>{};
              final count = counts[widget.section] ?? 0;
              final remaining = (5 - count).clamp(0, 5);

              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    remaining > 0 ? '$remaining left' : 'Limit reached',
                    style: TextStyle(
                      color: remaining > 0 ? Colors.white70 : Colors.orange,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isSaving
            ? null
            : () => _addItem({
                  'title': 'Example Item',
                  'description':
                      'Created at ${DateTime.now().toIso8601String()}',
                }),
        child: _isSaving
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Quota banner
          StreamBuilder<Map<String, int>>(
            stream: _quotaService.countsStream(widget.uid),
            builder: (context, snapshot) {
              final counts = snapshot.data ?? <String, int>{};
              final count = counts[widget.section] ?? 0;
              final remaining = (5 - count).clamp(0, 5);

              return Container(
                padding: const EdgeInsets.all(16.0),
                color:
                    remaining > 0 ? Colors.blue.shade50 : Colors.orange.shade50,
                child: Row(
                  children: [
                    Icon(
                      remaining > 0 ? Icons.info_outline : Icons.warning_amber,
                      color: remaining > 0 ? Colors.blue : Colors.orange,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Items in this section: $count of 5',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            remaining > 0
                                ? 'Free plan: $remaining slots remaining'
                                : 'Limit reached — upgrade for unlimited items',
                            style: TextStyle(
                              fontSize: 12,
                              color: remaining > 0
                                  ? Colors.black87
                                  : Colors.orange.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (remaining <= 2)
                      TextButton(
                        onPressed: () => _showUpgradeDialog(
                          const QuotaExceededException(
                            message: 'Unlock premium for unlimited entries.',
                          ),
                        ),
                        child: const Text('Upgrade'),
                      ),
                  ],
                ),
              );
            },
          ),
          // Items list
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text('No items yet. Tap + to add one.'),
                  )
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final entry = _items[index];
                      return ListTile(
                        leading: entry.isSynced
                            ? const Icon(Icons.check_circle,
                                color: Colors.green)
                            : const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                        title:
                            Text(entry.data['title']?.toString() ?? 'Untitled'),
                        subtitle: Text(
                          entry.data['description']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          entry.data['status']?.toString() ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                entry.isSynced ? Colors.green : Colors.orange,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
