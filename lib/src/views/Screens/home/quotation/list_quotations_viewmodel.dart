import 'dart:async';
import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/r2_quotation_media_service.dart'
    show QuotationMediaException, QuotationMediaFailure;
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'services/quotation_service.dart';

class QuotationListViewModel extends ChangeNotifier {
  QuotationListViewModel({
    QuotationService? quotationService,
    void Function(String message, Color color)? toast,
  })  : _quotationService = quotationService ?? QuotationService(),
        _toast = toast ?? _showPlatformToast {
    _initializeStream();
  }

  final QuotationService _quotationService;
  final void Function(String message, Color color) _toast;

  // Loading state
  final bool _isLoading = true;
  bool get isLoading => _isLoading;

  // Error state
  String? _error;
  String? get error => _error;

  // Quotations list
  final List<QuotationModel> _quotations = [];
  List<QuotationModel> get quotations => _quotations;

  // Stream subscription
  Stream<List<QuotationModel>>? _quotationsStream;
  Stream<List<QuotationModel>>? get quotationsStream => _quotationsStream;

  void _initializeStream() {
    // Q-1a: a failed re-read must not replace quotations already on screen
    // with the load-error state (a StreamBuilder drops its data on an error
    // event). Before the first list a failure still reaches the screen as
    // before; after it, the shown list stays — as the six entity lists do —
    // and the next successful read (or an authoritative empty list) replaces
    // it.
    var delivered = false;
    _quotationsStream = _quotationService.getUserQuotations().transform(
          StreamTransformer<List<QuotationModel>,
              List<QuotationModel>>.fromHandlers(
            handleData: (quotations, sink) {
              delivered = true;
              _refreshFailureReported = false;
              sink.add(quotations);
            },
            handleError: (error, stackTrace, sink) {
              if (!delivered) {
                sink.addError(error, stackTrace);
                return;
              }
              // The shown list stays; the person is told once per run of
              // failures (see [onRefreshFailed]).
              if (!_refreshFailureReported) {
                _refreshFailureReported = onRefreshFailed?.call() ?? false;
              }
            },
          ),
        );
  }

  /// Called when re-reading the list fails while quotations are shown. The
  /// screen says so, in the screen's existing way, when it is the one on top
  /// and returns true; false (not shown) leaves the next failure to say it.
  /// Not called again until a read succeeds.
  bool Function()? onRefreshFailed;
  bool _refreshFailureReported = false;

  // Refresh quotations
  Future<void> refreshQuotations() async {
    // The stream refreshes itself after every mutation
    _initializeStream();
  }

  /// A local file for the Quotation's PDF: this device's copy of that exact
  /// media object, or one download through a fresh short-lived signed link.
  /// Throws when it cannot be had.
  Future<File> resolvePdf(QuotationModel quotation) =>
      _quotationService.resolvePdfFile(quotation);

  /// [resolvePdf] for sharing: the same private local copy, but any failure is
  /// a [ShareFailure] carrying only a category, so no provider text, link or
  /// path can reach the Share dialog.
  Future<File> resolvePdfForShare(QuotationModel quotation) async {
    try {
      return await resolvePdf(quotation);
    } on QuotationMediaException catch (error) {
      throw ShareFailure(shareFailureKindOf(error.failure));
    } catch (_) {
      throw const ShareFailure(ShareFailureKind.generic);
    }
  }

  /// What a Quotation media failure means to a person who is sharing its PDF.
  static ShareFailureKind shareFailureKindOf(QuotationMediaFailure failure) {
    switch (failure) {
      case QuotationMediaFailure.notSignedIn:
      case QuotationMediaFailure.unauthorized:
        return ShareFailureKind.session;
      case QuotationMediaFailure.quotationNotFound:
        return ShareFailureKind.unavailable;
      case QuotationMediaFailure.interrupted:
      case QuotationMediaFailure.unavailable:
      case QuotationMediaFailure.uploadIncomplete:
      case QuotationMediaFailure.uploadRejected:
        return ShareFailureKind.network;
      default:
        return ShareFailureKind.generic;
    }
  }

  // Delete a quotation (soft delete: the row is hidden, never destroyed here)
  Future<void> deleteQuotation(String quotationId, BuildContext context) async {
    final loc = AppLocalizations.of(context);
    try {
      await _quotationService.deleteQuotation(quotationId);

      if (context.mounted) {
        _toast(loc.translate('quotationDeletedSuccessfully'), Colors.green);
      }
    } catch (_) {
      if (context.mounted) {
        _toast(loc.translate('quotationDeleteFailed'), Colors.red);
      }
    }
  }

  static void _showPlatformToast(String message, Color bgColor) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: bgColor,
      textColor: Colors.white,
    );
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
