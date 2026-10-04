import 'package:flutter/services.dart';

/// The system clipboard, behind an interface so the share logic around it runs
/// without a phone.
///
/// It exists for one reason: some receiving apps (WhatsApp is the one people
/// notice) ignore the message that comes with several files, so a share of two
/// or more photos or videos also leaves its message here, for the person to
/// paste once if the app did not show it.
abstract interface class ShareClipboard {
  /// Puts [text] on the clipboard. Completes with whether it was really put
  /// there. Never throws: a clipboard that cannot be written is a false, not a
  /// reason to stop the share.
  Future<bool> copy(String text);
}

/// The platform clipboard. Nothing is logged: the text is the person's chosen
/// message and is only ever handed to the system.
class SystemShareClipboard implements ShareClipboard {
  const SystemShareClipboard();

  @override
  Future<bool> copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (_) {
      return false;
    }
  }
}
