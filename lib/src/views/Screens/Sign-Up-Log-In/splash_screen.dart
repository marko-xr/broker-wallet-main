import 'package:flutter/material.dart';

import 'package:broker_wallet/src/constants/app_colors.dart';

/// Background for the existing bootstrap route underneath the launch animation.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.white,
      child: SizedBox.expand(),
    );
  }
}
