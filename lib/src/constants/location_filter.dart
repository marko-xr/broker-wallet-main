/// The kinds of place the map shows, and "all of them".
///
/// Kept apart from the colours (which need Flutter) so the code that decides
/// what the map shows can be plain Dart. `location_colors.dart` re-exports it,
/// so existing imports keep working.
enum LocationFilter { all, offers, owners, offices, watchmen }
