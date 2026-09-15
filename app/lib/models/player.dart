class Player {
  const Player({
    required this.nickname,
    required this.avatar,
    this.hint,
    this.isMe = false,
    this.isHost = false,
    this.isDisconnected = false,
  });

  final String nickname;
  final String avatar;

  /// `null` before the player's turn, empty when the turn passed without a hint.
  final String? hint;
  final bool isMe;
  final bool isHost;
  final bool isDisconnected;

  Player copyWith({String? hint, bool? isMe}) => Player(
        nickname: nickname,
        avatar: avatar,
        hint: hint ?? this.hint,
        isMe: isMe ?? this.isMe,
        isHost: isHost,
        isDisconnected: isDisconnected,
      );
}

/// The protocol avatar id: the asset file name without its extension.
String avatarIdOf(String asset) =>
    asset.substring(asset.lastIndexOf('/') + 1, asset.lastIndexOf('.'));

const avatarAssets = <String>[
  'assets/avatars/avatar-f01-notebook.webp',
  'assets/avatars/avatar-f02-camera.webp',
  'assets/avatars/avatar-f03-headphones.webp',
  'assets/avatars/avatar-f04-map.webp',
  'assets/avatars/avatar-f05-fingerprint-kit.webp',
  'assets/avatars/avatar-f06-laptop.webp',
  'assets/avatars/avatar-m01-flashlight.webp',
  'assets/avatars/avatar-m02-binoculars.webp',
  'assets/avatars/avatar-m03-evidence-bag.webp',
  'assets/avatars/avatar-m04-detective-hat.webp',
  'assets/avatars/avatar-m05-badge.webp',
  'assets/avatars/avatar-m06-magnifying-glass.webp',
];
