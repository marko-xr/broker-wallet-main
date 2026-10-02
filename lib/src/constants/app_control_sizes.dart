/// The sizes the app's reusable controls share.
///
/// A size lives here only when a *kind* of control has one, so that every
/// control of that kind is the same size and changing it is a one-line edit:
///
///  * a large action (Save, Cancel, Update, Done, a full-width confirm) is
///    [standardButtonHeight] tall;
///  * a compact inline action (a "Show more" toggle) has at least
///    [compactButtonHeight] to tap;
///  * a quick-pick chip has the [chipHorizontalPadding] / [chipVerticalPadding]
///    padding, [chipBorderWidth] border and [chipRadius] corners, and sits
///    [chipSpacing] from the next chip;
///  * nothing a person has to tap is smaller than [minTouchTarget].
///
/// Different kinds are deliberately NOT forced to one size: a chip, a text
/// field, an icon button and a large action each keep their own. Colours,
/// radii of the larger controls and type styles are not sizes and stay with
/// their own components.
class AppControlSizes {
  const AppControlSizes._();

  /// A large primary or secondary action: Save, Cancel, Update, Done, a
  /// full-width confirm.
  static const double standardButtonHeight = 48;

  /// The Save / Cancel pair of the add and edit forms. It is the standard large
  /// action, named separately so the forms read as what they are.
  static const double formActionHeight = standardButtonHeight;

  /// A compact inline action: the "Show more" / "Show less" toggle, a retry or
  /// other small utility link. Smaller than [standardButtonHeight] on purpose.
  static const double compactButtonHeight = 40;

  /// The smallest area a person is asked to hit.
  static const double minTouchTarget = 48;

  /// Padding between a quick-pick chip's border and its label, each side.
  static const double chipHorizontalPadding = 18;

  /// Padding between a quick-pick chip's border and its label, top and bottom.
  static const double chipVerticalPadding = 9;

  /// The border of a quick-pick chip.
  static const double chipBorderWidth = 1.3;

  /// The corner radius of a quick-pick chip: a pill.
  static const double chipRadius = 32;

  /// The gap between chips, both across a row and between rows. A layout that
  /// plans rows of chips has to plan with this same gap.
  static const double chipSpacing = 10;
}
