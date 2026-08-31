import 'package:flutter/material.dart';
import 'animated_search_hints.dart';

class SearchBar extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final List<String>? animatedHints;

  const SearchBar({
    super.key,
    required this.hint,
    required this.onChanged,
    this.animatedHints,
  });

  @override
  State<SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<SearchBar> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _hasFocus = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();

    _focusNode.addListener(() {
      setState(() => _hasFocus = _focusNode.hasFocus);
    });

    _controller.addListener(() {
      final txt = _controller.text;
      final hadText = _hasText;
      _hasText = txt.isNotEmpty;
      if (hadText != _hasText) setState(() {});
      widget.onChanged(txt);
      // No setState spam here unless _hasText flips; direction is computed in build
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _isAscii(String s) => s.runes.every((c) => c <= 0x007F);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dir = Directionality.of(context);

    // Show animated hints only when not focused and no text
    final showAnimatedHints =
        !_hasFocus && !_hasText && (widget.animatedHints?.isNotEmpty ?? false);

    // Force LTR while typing ASCII-only to keep IDs/phones/IBAN readable in Arabic UI
    final computedDirection =
        (_hasText && _isAscii(_controller.text)) ? TextDirection.ltr : dir;

    return Directionality(
      textDirection: computedDirection,
      child: Container(
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
        child: Stack(
          children: [
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => widget.onChanged(v),
              decoration: InputDecoration(
                // Hide static hint when animated hints are visible
                hintText: showAnimatedHints ? null : widget.hint,
                hintStyle: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
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
                        tooltip: MaterialLocalizations.of(context)
                            .deleteButtonTooltip,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                        onPressed: () {
                          _controller.clear();
                          widget.onChanged('');
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surface,
                contentPadding:
                    const EdgeInsetsDirectional.symmetric(vertical: 16),
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
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 2,
                  ),
                ),
              ),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),

            // Animated hints overlay (directional)
            if (showAnimatedHints)
              PositionedDirectional(
                start: 50, // accounts for search icon space
                end: 16,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AnimatedSearchHints(
                      hints: widget.animatedHints!,
                      duration: const Duration(milliseconds: 2500),
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
