import 'package:flutter/material.dart';

/// Arguments for [InfoPlaceholderView].
///
/// Used for Profile/Settings destinations that do not have their
/// implementation yet (Privacy Policy, Terms & Conditions, Help & Support,
/// Contact Us, Security, Export Data). The view never invents policy,
/// legal, or contact content — it only communicates that the destination
/// is not available yet, honestly and consistently.
class InfoPlaceholderArgs {
  final String title;
  final String message;
  final IconData icon;

  const InfoPlaceholderArgs({
    required this.title,
    required this.message,
    this.icon = Icons.hourglass_top_rounded,
  });
}
