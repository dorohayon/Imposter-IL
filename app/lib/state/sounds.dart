import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A moment the game marks with a sound (docs/decisions.md, "צלילים").
/// The files are in assets/sounds/, with their source and license.
enum Sound {
  revealCitizen('reveal_citizen'),
  revealImposter('reveal_imposter'),
  voteStart('vote_start'),
  win('win'),
  lose('lose'),
  unlock('unlock'),
  reaction('reaction'),

  /// The last five seconds of a timer, its final hit on zero.
  countdown('countdown');

  const Sound(this.file);
  final String file;
}

/// Music that loops quietly under a whole stage of the game.
enum Bed {
  voting('vote_bed');

  const Bed(this.file);
  final String file;
}

/// The game's sounds: one-shot effects, and a bed that loops under a stage.
///
/// Sounds mix with the player's own music and keep quiet on an iPhone set to
/// silent. One that fails to play is dropped: a sound is never worth an error.
class Sounds {
  Sounds._() {
    if (_real) {
      unawaited(_guard(() => AudioPlayer.global.setAudioContext(
            AudioContextConfig(
              focus: AudioContextConfigFocus.mixWithOthers,
              respectSilence: true,
            ).build(),
          )));
      // Nothing plays on behind another app: the bed pauses, effects stop,
      // and a timer that fires meanwhile finds [play] closed.
      _lifecycle = AppLifecycleListener(
        onHide: () {
          _hidden = true;
          for (final s in _effects.keys.toList()) {
            stop(s);
          }
          _bedTicket++;
          if (_bedPlayer case final player?) unawaited(_guard(player.stop));
        },
        onShow: () {
          _hidden = false;
          if (_bed case final bed? when _enabled) _playBed(bed);
        },
      );
    }
  }

  static final instance = Sounds._();

  /// Widget tests have no audio plugin; they read [played] instead.
  static final _real = !Platform.environment.containsKey('FLUTTER_TEST');

  static const _bedVolume = .35;

  // ignore: unused_field
  AppLifecycleListener? _lifecycle;
  final _effects = <Sound, AudioPlayer>{};
  AudioPlayer? _bedPlayer;
  Bed? _bed;
  bool _bedPlaying = false;
  bool _enabled = true;
  bool _hidden = false;

  /// Tickets for what should be playing. Starting a sound takes a few awaits;
  /// a stop, the switch or the app hiding in between takes a new ticket, and
  /// the start that finds its own gone does not play.
  final _tickets = <Sound, int>{};
  int _bedTicket = 0;

  /// What played, newest last: effects by file name, a bed as `bed:` and
  /// its file name, and a bed's end as `bed:off`.
  @visibleForTesting
  final played = <String>[];

  bool get enabled => _enabled;

  /// The Sounds switch in Settings.
  set enabled(bool on) {
    if (on == _enabled) return;
    _enabled = on;
    if (!on) {
      for (final s in _effects.keys.toList()) {
        stop(s);
      }
      _stopBed();
    } else if (_bed case final bed?) {
      _startBed(bed);
    }
  }

  /// The system click of a tap, on iPhone. Android plays its own on every
  /// Material tap, following the phone's Touch sounds setting, and iOS plays
  /// none unless asked.
  void click() {
    if (_enabled && _real && Platform.isIOS) {
      unawaited(_guard(() => SystemSound.play(SystemSoundType.click)));
    }
  }

  /// Plays [sound], [from] into it: a countdown that starts late still ends
  /// on zero.
  void play(Sound sound, {Duration from = Duration.zero}) {
    if (!_enabled || _hidden) return;
    played.add(sound.file);
    if (!_real) return;
    final player = _effects[sound] ??= AudioPlayer();
    final ticket = _tickets[sound] = (_tickets[sound] ?? 0) + 1;
    bool current() => _tickets[sound] == ticket && _enabled && !_hidden;
    unawaited(_guard(() async {
      await player.stop();
      if (!current()) return;
      await player.play(AssetSource('sounds/${sound.file}.m4a'),
          position: from);
      if (!current()) await player.stop();
    }));
  }

  /// Cuts a sound short, such as a countdown whose timer ended early.
  void stop(Sound sound) {
    _tickets[sound] = (_tickets[sound] ?? 0) + 1;
    final player = _effects[sound];
    if (player != null) unawaited(_guard(player.stop));
  }

  /// The bed that should be playing now, or null for none. Called on every
  /// change of stage; asking for the bed already playing changes nothing.
  void loop(Bed? bed) {
    if (bed == _bed) return;
    _bed = bed;
    if (bed == null) {
      _stopBed();
    } else if (_enabled) {
      _startBed(bed);
    }
  }

  void _startBed(Bed bed) {
    _bedPlaying = true;
    played.add('bed:${bed.file}');
    // Behind another app it waits, and starts when the app is back.
    if (_real && !_hidden) _playBed(bed);
  }

  void _playBed(Bed bed) {
    final player = _bedPlayer ??= AudioPlayer();
    final ticket = ++_bedTicket;
    bool current() =>
        _bedTicket == ticket && _bed == bed && _enabled && !_hidden;
    unawaited(_guard(() async {
      await player.stop();
      await player.setReleaseMode(ReleaseMode.loop);
      if (!current()) return;
      await player.play(AssetSource('sounds/${bed.file}.m4a'),
          volume: _bedVolume);
      if (!current()) await player.stop();
    }));
  }

  void _stopBed() {
    _bedTicket++;
    if (!_bedPlaying) return;
    _bedPlaying = false;
    played.add('bed:off');
    if (_bedPlayer case final player?) unawaited(_guard(player.stop));
  }

  static Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (e) {
      debugPrint('[sounds] $e');
    }
  }
}

/// The app's sounds.
Sounds get sounds => Sounds.instance;

/// [onTap] with the system click in front of it; null stays null, so a
/// disabled button stays disabled.
VoidCallback? withClick(VoidCallback? onTap) => onTap == null
    ? null
    : () {
        sounds.click();
        onTap();
      };
