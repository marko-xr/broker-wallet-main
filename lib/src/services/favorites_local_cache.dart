import 'encrypted_account_list_cache.dart';

/// Favorites-cache keys in secure storage, under
/// `favorites_cache_key_v1_<uid>`.
class SecureFavoritesCacheKeyStore extends SecureAccountCacheKeyStore {
  const SecureFavoritesCacheKeyStore() : super(prefix: _prefix);

  static const String _prefix = 'favorites_cache_key_v1_';

  static String storageKeyFor(String uid) => '$_prefix$uid';
}

/// One saved favorite, as the Favorites screen draws its card: plain values
/// only, so it never ties this file to the Favorites screen's own types.
///
/// [media] is the card media's stored identity (`FavoriteCardMedia`'s
/// `toStored`): a stable cache key and whether it is a video, never a link.
/// No URL of any kind is kept — a card's `imageUrl` can be a short-lived
/// signed link, so it is left out.
class StoredFavorite {
  const StoredFavorite({
    required this.account,
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.addedAt,
    this.media,
  });

  /// The account the favorite belongs to (the signed-in Supabase user id).
  final String account;
  final String id;
  final String type;
  final String title;
  final String subtitle;
  final DateTime addedAt;
  final String? media;
}

/// Each account's saved Favorites, decrypted, for this process only, so a
/// Favorites screen built after the first read draws them in its first frame.
/// Never written anywhere.
///
/// It lives here, beside the cache, rather than in the Favorites service: the
/// app reaches that service under two import spellings, which Dart would treat
/// as two libraries with two separate copies of any static state. This file
/// has one spelling, so clearing it (account change, Delete Account) always
/// clears the one copy there is.
abstract final class FavoritesMemory {
  static final Map<String, ({List<StoredFavorite> items, bool fromPlaintext})>
      _byAccount = {};

  /// [uid]'s saved favorites, and whether they came from the old plaintext
  /// copy; null when none are held.
  static ({List<StoredFavorite> items, bool fromPlaintext})? of(String uid) =>
      _byAccount[uid];

  static void put(
    String uid,
    List<StoredFavorite> items, {
    required bool fromPlaintext,
  }) =>
      _byAccount[uid] = (
        items: List<StoredFavorite>.unmodifiable(items),
        fromPlaintext: fromPlaintext,
      );

  static void forget(String uid) => _byAccount.remove(uid);

  static void forgetAll() => _byAccount.clear();

  /// The on-screen items made from the old plaintext copy. They are shown,
  /// but never written into the encrypted copy: an old file (possibly one
  /// restored from a backup) must not become an authenticated list.
  static final Expando<bool> _plaintextItems = Expando<bool>('plaintext');

  static void markPlaintext(Object item) => _plaintextItems[item] = true;

  static bool isPlaintext(Object item) => _plaintextItems[item] == true;
}

/// The last complete Favorites list the server returned for an account,
/// encrypted on this device so the Favorites screen can show it when the
/// network is unavailable. See [EncryptedAccountListCache] for the rules it
/// follows: per-account key in secure storage, an authenticated list, a box
/// in the backup-excluded lists directory, and fail-closed reads.
///
/// The box prefix is new on purpose. The older plaintext copy lives in the
/// documents directory as `cached_favorites_<uid>`, and the encrypted cache
/// moves a box of its own name from there into its directory; sharing that
/// name would move the plaintext box in and then fail to open it.
class FavoritesLocalCache extends EncryptedAccountListCache<StoredFavorite> {
  const FavoritesLocalCache({
    AccountCacheKeyStore keyStore = const SecureFavoritesCacheKeyStore(),
  }) : super(
          boxPrefix: _boxPrefix,
          listKey: 'favorites_v1',
          logName: 'FavoritesCache',
          keyStore: keyStore,
          encode: encodeRecord,
          decode: _decode,
          ownerOf: _accountOf,
          idOf: _idOf,
        );

  static const String _boxPrefix = 'favorites_v1_';

  /// The account's box name; also used by tests.
  static String boxNameForUid(String uid) => '$_boxPrefix$uid';

  static String _accountOf(StoredFavorite f) => f.account;

  static String? _idOf(StoredFavorite f) => '${f.type}:${f.id}';

  /// What is stored for [f]; public so tests can check no link is kept.
  static Map<String, Object?> encodeRecord(StoredFavorite f) => {
        'account': f.account,
        'id': f.id,
        'type': f.type,
        'title': f.title,
        'subtitle': f.subtitle,
        'addedAt': f.addedAt.toUtc().toIso8601String(),
        'media': f.media,
      };

  static StoredFavorite _decode(Map<String, dynamic> m) => StoredFavorite(
        account: m['account'] as String,
        id: m['id'] as String,
        type: m['type'] as String,
        title: m['title'] as String,
        subtitle: m['subtitle'] as String,
        addedAt: DateTime.parse(m['addedAt'] as String),
        media: m['media'] as String?,
      );
}
