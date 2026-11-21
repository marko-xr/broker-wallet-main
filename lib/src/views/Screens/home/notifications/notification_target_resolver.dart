import 'dart:async';

// Deliberately imports nothing under `src/views`: app.dart reaches this file
// as `src/Views/...`, and a second spelling would load a second library copy.
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/request_service.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:flutter/material.dart';

/// Looks a record up by id; null when it is not there or cannot be read.
typedef RecordLookup<T> = Future<T?> Function(String id);

/// Finds a reminder's Request or Offer: the copy already on this phone (the
/// account's encrypted list cache) first, then the server within
/// [fetchBudget]. Never throws; a record whose id is not exactly the one
/// asked for is ignored.
class NotificationRecordLookup {
  NotificationRecordLookup({
    required this.cachedRequest,
    required this.fetchRequest,
    required this.cachedOffer,
    required this.fetchOffer,
    this.fetchBudget = const Duration(seconds: 2),
  });

  /// The app's sources for the signed-in account [uid]; with no account
  /// nothing is found.
  factory NotificationRecordLookup.forAccount(String? uid) {
    if (uid == null) {
      Future<Never?> none(String _) async => null;
      return NotificationRecordLookup(
        cachedRequest: none,
        fetchRequest: none,
        cachedOffer: none,
        fetchOffer: none,
      );
    }
    return NotificationRecordLookup(
      cachedRequest: (id) async => _byId(
        await const RequestsLocalCache().read(uid),
        id,
        (request) => request.id,
      ),
      fetchRequest: RequestService().getRequest,
      cachedOffer: (id) async => _byId(
        await const OffersLocalCache().read(uid),
        id,
        (offer) => offer.id,
      ),
      fetchOffer: OfferService().getOfferMetadata,
    );
  }

  final RecordLookup<RequestModel> cachedRequest;
  final RecordLookup<RequestModel> fetchRequest;
  final RecordLookup<OfferModel> cachedOffer;
  final RecordLookup<OfferModel> fetchOffer;
  final Duration fetchBudget;

  Future<RequestModel?> findRequest(String id) =>
      _find(id, cachedRequest, fetchRequest, (r) => r.id);

  Future<OfferModel?> findOffer(String id) =>
      _find(id, cachedOffer, fetchOffer, (o) => o.id);

  Future<T?> _find<T>(
    String id,
    RecordLookup<T> cached,
    RecordLookup<T> fetch,
    String? Function(T) idOf,
  ) async {
    T? valid(T? record) =>
        record != null && idOf(record)?.trim() == id ? record : null;
    try {
      final local = valid(await cached(id));
      if (local != null) return local;
    } catch (_) {
      // An unreadable cache is the same as no copy.
    }
    try {
      return valid(await fetch(id).timeout(fetchBudget));
    } catch (_) {
      return null;
    }
  }

  static T? _byId<T>(List<T>? items, String id, String? Function(T) idOf) {
    if (items == null) return null;
    for (final item in items) {
      if (idOf(item)?.trim() == id) return item;
    }
    return null;
  }
}

/// The body of an inbox-opened details route. It starts while the fade
/// through is still covering the inbox, so a record found on the phone is
/// ready before the screen shows: no loading screen and no wait before the
/// motion. Until the record is found the page stays the plain background;
/// only after [spinnerDelay] does a loading indicator appear. If nothing is
/// found, [fallback] (the regular by-id screen, with its "not found" state)
/// takes over.
class NotificationRecordScreen<T extends Object> extends StatefulWidget {
  const NotificationRecordScreen({
    super.key,
    required this.find,
    required this.details,
    required this.fallback,
    this.spinnerDelay = const Duration(milliseconds: 400),
  });

  final Future<T?> Function() find;
  final Widget Function(T record) details;
  final WidgetBuilder fallback;
  final Duration spinnerDelay;

  @override
  State<NotificationRecordScreen<T>> createState() =>
      _NotificationRecordScreenState<T>();
}

class _NotificationRecordScreenState<T extends Object>
    extends State<NotificationRecordScreen<T>> {
  late final Future<T?> _record = widget.find();
  Timer? _spinnerTimer;
  bool _showSpinner = false;

  @override
  void initState() {
    super.initState();
    _spinnerTimer = Timer(widget.spinnerDelay, () {
      if (mounted) setState(() => _showSpinner = true);
    });
  }

  @override
  void dispose() {
    _spinnerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T?>(
      future: _record,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          _spinnerTimer?.cancel();
          final record = snapshot.data;
          return record == null
              ? widget.fallback(context)
              : widget.details(record);
        }
        return Scaffold(
          key: const ValueKey('notification-record-waiting'),
          appBar: _showSpinner ? AppBar() : null,
          body: _showSpinner
              ? const Center(child: CircularProgressIndicator())
              : const SizedBox.expand(),
        );
      },
    );
  }
}
