/// The room counts the Offer and Request forms offer: 1 to 6, and "7+" as
/// their last choice, stored as [orMore].
abstract final class RoomCount {
  /// The stored value of the "7+" choice.
  static const int orMore = 7;

  /// How a stored room count reads: [orMore] reads "7+", any other count as
  /// itself.
  static String label(int rooms) => rooms == orMore ? '$orMore+' : '$rooms';

  /// [label] kept left-to-right inside Arabic text, so "7+" never shows as
  /// "+7" (a left-to-right isolate around it).
  static String display(int rooms) =>
      rooms == orMore ? '\u2066${label(rooms)}\u2069' : label(rooms);
}
