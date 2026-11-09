import '../data/models/ScreensModel/brokers_model.dart';
import '../data/models/ScreensModel/offices_model.dart';
import '../data/models/ScreensModel/owners_model.dart';
import '../data/models/ScreensModel/request_model.dart';
import '../data/models/ScreensModel/watchmen_model.dart';
import '../repositories/repository_provider.dart';
import 'brokers_local_cache.dart';
import 'list_session_check.dart';
import 'offices_local_cache.dart';
import 'owners_local_cache.dart';
import 'requests_local_cache.dart';
import 'watchmen_local_cache.dart';

/// Finds a favorite's record in the signed-in account's own saved list.
///
/// A favorite drawn from the saved Favorites copy carries no record, and the
/// Requests, Owners, Offices, Brokers and Watchmen details screens need one.
/// This looks it up in the same encrypted list its own list screen shows when
/// offline, so the details open with exactly the record that screen would
/// open them with. Nothing is made up: a record that list does not hold is
/// not found.
///
/// The saved lists keep their own rules: a list is read only for the account
/// it belongs to, only after its integrity check, only with that account's
/// records, and never with a record whose deletion the server confirmed.
/// Here, a different account or session by the time the read finishes means
/// nothing is found. Offers are not looked up: their details open by id.
class FavoriteSavedRecords {
  const FavoriteSavedRecords({
    String? Function() currentUserId = _signedInAccount,
    String? Function() currentSession = ListSessionCheck.currentSession,
    RequestsLocalCache requests = const RequestsLocalCache(),
    OwnersLocalCache owners = const OwnersLocalCache(),
    OfficesLocalCache offices = const OfficesLocalCache(),
    BrokersLocalCache brokers = const BrokersLocalCache(),
    WatchmenLocalCache watchmen = const WatchmenLocalCache(),
  })  : _currentUserId = currentUserId,
        _currentSession = currentSession,
        _requests = requests,
        _owners = owners,
        _offices = offices,
        _brokers = brokers,
        _watchmen = watchmen;

  final String? Function() _currentUserId;
  final String? Function() _currentSession;
  final RequestsLocalCache _requests;
  final OwnersLocalCache _owners;
  final OfficesLocalCache _offices;
  final BrokersLocalCache _brokers;
  final WatchmenLocalCache _watchmen;

  static String? _signedInAccount() {
    try {
      return RepositoryProvider.instance.authRepository.currentUserId;
    } catch (_) {
      return null;
    }
  }

  /// The saved record [id] of the favorite [type] (`requests`, `owners`,
  /// `offices`, `brokers` or `watchmen`), or null when there is none to use.
  /// Never throws.
  Future<Object?> find(String type, String id) async {
    final wanted = id.trim();
    final String? uid;
    final String? session;
    try {
      uid = _currentUserId();
      session = _currentSession();
    } catch (_) {
      return null;
    }
    if (uid == null || uid.isEmpty || wanted.isEmpty) return null;

    try {
      final Object? found = switch (type) {
        'requests' =>
          _pick<RequestModel>(await _requests.read(uid), (r) => r.id, wanted),
        'owners' =>
          _pick<OwnerModel>(await _owners.read(uid), (o) => o.id, wanted),
        'offices' =>
          _pick<OfficeModel>(await _offices.read(uid), (o) => o.id, wanted),
        'brokers' =>
          _pick<BrokerModel>(await _brokers.read(uid), (b) => b.id, wanted),
        'watchmen' =>
          _pick<WatchmenModel>(await _watchmen.read(uid), (w) => w.id, wanted),
        _ => null,
      };
      if (_currentUserId() != uid || _currentSession() != session) {
        return null;
      }
      return found;
    } catch (_) {
      return null;
    }
  }

  static T? _pick<T>(List<T>? items, String? Function(T) idOf, String id) {
    if (items == null) return null;
    for (final item in items) {
      if (idOf(item)?.trim() == id) return item;
    }
    return null;
  }
}
