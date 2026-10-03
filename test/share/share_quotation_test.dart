// What a person who is sharing a quotation's PDF is told when the PDF cannot be
// had. The Quotation's own download, cache and signing are tested with the
// Quotation service; this covers how its failures reach the Share dialog.

import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/Views/Screens/home/quotation/list_quotations_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/r2_quotation_media_service.dart'
    show QuotationMediaFailure;
import 'package:broker_wallet/src/services/share/share_models.dart';

void main() {
  group('a quotation PDF that cannot be had', () {
    test('a signed-out session is a session failure', () {
      for (final failure in <QuotationMediaFailure>[
        QuotationMediaFailure.notSignedIn,
        QuotationMediaFailure.unauthorized,
      ]) {
        expect(QuotationListViewModel.shareFailureKindOf(failure),
            ShareFailureKind.session,
            reason: failure.name);
      }
    });

    test('a quotation that no longer exists is unavailable for good', () {
      expect(
        QuotationListViewModel.shareFailureKindOf(
            QuotationMediaFailure.quotationNotFound),
        ShareFailureKind.unavailable,
      );
    });

    test('a dropped connection or an unreachable service is worth retrying',
        () {
      for (final failure in <QuotationMediaFailure>[
        QuotationMediaFailure.interrupted,
        QuotationMediaFailure.unavailable,
        QuotationMediaFailure.uploadIncomplete,
        QuotationMediaFailure.uploadRejected,
      ]) {
        expect(QuotationListViewModel.shareFailureKindOf(failure),
            ShareFailureKind.network,
            reason: failure.name);
      }
    });

    test('anything else is a generic failure, never a guess', () {
      for (final failure in <QuotationMediaFailure>[
        QuotationMediaFailure.staleReplacement,
        QuotationMediaFailure.unsupportedType,
        QuotationMediaFailure.tooLarge,
        QuotationMediaFailure.typeMismatch,
        QuotationMediaFailure.invalidResponse,
        QuotationMediaFailure.notConfigured,
        QuotationMediaFailure.unknown,
      ]) {
        expect(QuotationListViewModel.shareFailureKindOf(failure),
            ShareFailureKind.generic,
            reason: failure.name);
      }
    });

    test('every failure the service can raise has an answer', () {
      for (final failure in QuotationMediaFailure.values) {
        expect(QuotationListViewModel.shareFailureKindOf(failure), isNotNull,
            reason: failure.name);
      }
    });
  });
}
