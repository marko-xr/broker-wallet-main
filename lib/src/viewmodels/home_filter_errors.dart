import 'package:broker_wallet/src/views/Screens/home/search/search_viewmodel.dart'
    show SearchErrorKind, classifySearchError;

import 'home_filter_controller.dart';

/// Sorts a failure to read the records into a [HomeFilterErrorKind].
///
/// It is the classification Search already uses for the same reads, so a
/// connection problem, an expired session and anything else are told apart the
/// same way on both screens. The technical error is never shown to anyone.
HomeFilterErrorKind classifyHomeFilterError(Object error) {
  switch (classifySearchError(error)) {
    case SearchErrorKind.network:
      return HomeFilterErrorKind.network;
    case SearchErrorKind.session:
      return HomeFilterErrorKind.session;
    case SearchErrorKind.generic:
      return HomeFilterErrorKind.generic;
  }
}
