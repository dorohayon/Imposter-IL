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
  final String? hint;
  final bool isMe;
  final bool isHost;
  final bool isDisconnected;
}

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

const demoPlayers = <Player>[
  Player(nickname: 'נועם', avatar: 'assets/avatars/avatar-f01-notebook.webp', hint: 'מתוק', isMe: true),
  Player(nickname: 'יובל', avatar: 'assets/avatars/avatar-m02-binoculars.webp', hint: 'קיץ'),
  Player(nickname: 'מאיה', avatar: 'assets/avatars/avatar-f02-camera.webp', hint: 'קר'),
  Player(nickname: 'אורי', avatar: 'assets/avatars/avatar-m04-detective-hat.webp', hint: 'כדור'),
  Player(nickname: 'דנה', avatar: 'assets/avatars/avatar-f04-map.webp', hint: 'צהוב'),
  Player(nickname: 'רועי', avatar: 'assets/avatars/avatar-m05-badge.webp', hint: 'קליפה'),
];
