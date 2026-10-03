import 'package:flutter/material.dart';
import 'package:broker_wallet/src/constants/app_control_sizes.dart';
import 'animated_search_hints.dart';

class SearchBar extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  /// The keyboard's Search action. When absent it reports through [onChanged].
  final ValueChanged<String>? onSubmitted;
  final List<String>? animatedHints;

  const SearchBar({
    super.key,
    required this.hint,
    required this.onChanged,
    this.onSubmitted,
    this.animatedHints,
  });

  @override
  State<SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<SearchBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _hasFocus = false;
  bool _hasText = false;
  bool _asciiOnly = true;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_hasFocus == _focusNode.hasFocus) return;
    setState(() => _hasFocus = _focusNode.hasFocus);
  }

  /// A [TextEditingController] also notifies when only the cursor or selection
  /// moves. That is not a new query, so only a change of the TEXT is reported:
  /// moving the cursor must not restart a search.
  void _onTextChanged() {
    final text = _controller.text;
    if (text == _lastText) return;
    _lastText = text;

    final hasText = text.isNotEmpty;
    final asciiOnly = _isAscii(text);
    if (hasText != _hasText || asciiOnly != _asciiOnly) {
      setState(() {
        _hasText = hasText;
        _asciiOnly = asciiOnly;
      });
    }
    widget.onChanged(text);
  }

  static bool _isAscii(String s) => s.runes.every((c) => c <= 0x007F);

  void _clear() {
    // Clearing notifies the listener, which reports the empty query once.
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // The rotating hint shows only while the field is empty and idle.
    final showAnimatedHints =
        !_hasFocus && !_hasText && (widget.animatedHints?.isNotEmpty ?? false);

    // Typing ASCII-only (an ID, a phone number) in an Arabic UI reads as LTR.
    // Only the typed TEXT takes that direction: the search icon, the clear
    // button and the hint stay where they are, so typing the first character
    // moves nothing but the text.
    final TextDirection? textDirection =
        (_hasText && _asciiOnly) ? TextDirection.ltr : null;

    final fieldStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: colorScheme.onSurface,
    );
    final hintStyle = TextStyle(
      color: colorScheme.onSurface.withValues(alpha: 0.6),
      fontSize: 16,
      fontWeight: FontWeight.w400,
    );
    // The rotating hint is not drawn by the field, so it must be given the
    // style the field gives its own hint — the theme's input text style, then
    // the field's style, then the hint style — or its size, letter spacing and
    // line box would differ from the static hint it hands over to.
    final rotatingHintStyle = (theme.useMaterial3
                ? theme.textTheme.bodyLarge
                : theme.textTheme.titleMedium)
            ?.merge(fieldStyle)
            .merge(hintStyle) ??
        hintStyle;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        textInputAction: TextInputAction.search,
        textDirection: textDirection,
        onSubmitted: (value) =>
            (widget.onSubmitted ?? widget.onChanged).call(value),
        decoration: InputDecoration(
          // The rotating hint is the field's own hint, laid out by the field
          // exactly where its static hint is: it has the same origin focused
          // or not, from the first frame, and no position is computed here.
          // (The decoration takes a hint widget OR hint text, never both.)
          hint: showAnimatedHints
              ? Semantics(
                  // Screen readers get the stable hint, not whichever
                  // suggestion happens to be showing.
                  label: widget.hint,
                  excludeSemantics: true,
                  child: IgnorePointer(
                    child: AnimatedSearchHints(
                      hints: widget.animatedHints!,
                      duration: const Duration(milliseconds: 2500),
                      style: rotatingHintStyle,
                    ),
                  ),
                )
              : null,
          // The static hint: shown while the field is focused.
          hintText: showAnimatedHints ? null : widget.hint,
          hintStyle: hintStyle,
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              Icons.search_rounded,
              color: _hasFocus
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.6),
              size: 22,
            ),
          ),
          suffixIcon: _hasText
              ? IconButton(
                  tooltip:
                      MaterialLocalizations.of(context).deleteButtonTooltip,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                  onPressed: _clear,
                )
              : null,
          filled: true,
          fillColor: colorScheme.surface,
          // 12 above and below the one 24 dp text line: the field is 48 high, the
          // minimum interactive size (it was 56 with 16).
          contentPadding: const EdgeInsetsDirectional.symmetric(
            vertical: AppControlSizes.searchFieldVerticalPadding,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(
              color: colorScheme.outline.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          // Primary, and thin. A border is painted inside the field, so its
          // width never changes the field's size: focused and unfocused are the
          // same box.
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(
              color: colorScheme.primary,
              width: AppControlSizes.focusedFieldBorderWidth,
            ),
          ),
        ),
        style: fieldStyle,
      ),
    );
  }
}
