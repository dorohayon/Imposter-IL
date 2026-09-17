import 'server.dart';

/// Room invitations travel as a link, because a bare six-digit code is not
/// something a friend can tap in a chat.
Uri inviteLink(String roomCode) =>
    defaultServerUrl().resolve('/join/$roomCode');

/// The room code inside an invitation, or null if this is not one.
///
/// Both forms arrive here: the https link that was shared, and the
/// `imposteril://join/123456` the invitation page hands to the app. The
/// platform delivers them as a route string, so a bare `/join/123456` counts
/// too.
String? roomCodeFromLink(String? link) {
  if (link == null || link.isEmpty) return null;
  final match = RegExp(r'(?:^|/)join/(\d{6})/?$').firstMatch(link.trim());
  return match?.group(1);
}
