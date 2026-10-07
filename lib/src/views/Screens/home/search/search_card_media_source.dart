import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';

import 'search_card_media.dart';

/// The app's own media: what the Offer and Owner services hold on this device,
/// and what the media Worker lists for a record. Both services reach Supabase
/// only when first asked, so building this costs nothing.
class DefaultSearchCardMediaSource implements SearchCardMediaSource {
  DefaultSearchCardMediaSource({OfferService? offers, OwnerService? owners})
      : _offersGiven = offers,
        _ownersGiven = owners;

  final OfferService? _offersGiven;
  final OwnerService? _ownersGiven;

  late final OfferService _offers = _offersGiven ?? OfferService();
  late final OwnerService _owners = _ownersGiven ?? OwnerService();

  @override
  String? get accountId => _offers.currentOwnerId;

  @override
  List<OfferMediaRef> cached(CardMediaKind kind, String recordId) {
    switch (kind) {
      case CardMediaKind.offer:
        return _offers.cachedOfferMedia(recordId);
      case CardMediaKind.owner:
        return _owners.cachedMedia(recordId);
    }
  }

  @override
  Future<OfferMediaResolution?> resolve(
    CardMediaKind kind,
    String recordId,
    String accountId,
  ) {
    switch (kind) {
      case CardMediaKind.offer:
        return _offers.resolveOfferMedia(
          offerId: recordId,
          ownerId: accountId,
        );
      case CardMediaKind.owner:
        return _owners.resolveMedia(recordId: recordId, ownerId: accountId);
    }
  }
}
