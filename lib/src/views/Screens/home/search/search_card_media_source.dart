import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';

import 'search_card_media.dart';

/// The app's own media: what the Offer and Owner services hold on this device,
/// and what the media Worker lists for a record. Both services reach Supabase
/// only when first asked, so building this costs nothing.
///
/// Its saved-ids lookup ([SearchCardHeldMedia]) is used only by a resolver
/// given it as `heldMedia` (Search, tracker §7AZ, M3b-2): the services'
/// read-only M2-3 helpers, which follow the catalogue when the record has an
/// entry, check the account and its authorized session, and never download or
/// write anything.
class DefaultSearchCardMediaSource
    implements SearchCardMediaSource, SearchCardHeldMedia {
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
  List<OfferMediaRef> listed(
    CardMediaKind kind,
    String recordId,
    String accountId,
    List<String> ids,
  ) {
    switch (kind) {
      case CardMediaKind.offer:
        return _offers.listedOfferMedia(recordId, ownerId: accountId, ids: ids);
      case CardMediaKind.owner:
        return _owners.listedMedia(recordId, ownerId: accountId, ids: ids);
    }
  }

  @override
  Future<List<OfferMediaRef>> discover(
    CardMediaKind kind,
    String recordId,
    String accountId,
    List<String> ids,
  ) {
    switch (kind) {
      case CardMediaKind.offer:
        return _offers.discoverHeldOfferMedia(recordId,
            ownerId: accountId, ids: ids);
      case CardMediaKind.owner:
        return _owners.discoverHeldMedia(recordId,
            ownerId: accountId, ids: ids);
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
