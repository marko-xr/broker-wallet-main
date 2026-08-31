import 'package:flutter/material.dart';

class BaseActionDecoration extends BoxDecoration {
  BaseActionDecoration({
    required Color backgroundColor,
    required Color shadowColor,
  }) : super(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 8,
              spreadRadius: 0,
              offset: const Offset(0, 1),
            ),
          ],
        );
}

class BackActionDecoration extends BaseActionDecoration {
  BackActionDecoration(ColorScheme colors)
      : super(
          backgroundColor: colors.surface.withValues(alpha: 0.95),
          shadowColor: colors.shadow.withValues(alpha: 0.12),
        );
}

class FavoriteActionDecoration extends BaseActionDecoration {
  FavoriteActionDecoration(ColorScheme colors)
      : super(
          backgroundColor: colors.surface.withValues(alpha: 0.95),
          shadowColor: colors.shadow.withValues(alpha: 0.12),
        );
}

class ShareActionDecoration extends BaseActionDecoration {
  ShareActionDecoration(ColorScheme colors)
      : super(
          backgroundColor: colors.surface.withValues(alpha: 0.95),
          shadowColor: colors.shadow.withValues(alpha: 0.12),
        );
}

class DeleteActionDecoration extends BaseActionDecoration {
  DeleteActionDecoration(ColorScheme colors)
      : super(
          backgroundColor: const Color(0xFFC81E1E).withValues(alpha: 0.1),
          shadowColor: colors.shadow.withValues(alpha: 0.12),
        );
}
