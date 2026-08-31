// lib/src/widgets/rating_bar.dart
import 'package:flutter/material.dart';

class RatingBar extends StatelessWidget {
  final int rating;
  final ValueChanged<int> onRatingChanged;

  const RatingBar(
      {super.key, required this.rating, required this.onRatingChanged});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final starNum = index + 1;
        return IconButton(
          iconSize: 40,
          onPressed: () => onRatingChanged(starNum),
          icon: Icon(
            starNum <= rating ? Icons.star : Icons.star_border,
            color: starNum <= rating
                ? primary
                : Color.fromARGB((0.3 * 255).round(), primary.red,
                    primary.green, primary.blue),
          ),
        );
      }),
    );
  }
}
