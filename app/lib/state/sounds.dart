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
      // A bed must not play on behind another app.
      _lifecycle = AppLifecycleListener(
        onHide: () => _guard(() async => _bedPlayer?.pause()),
        onShow: () => _guard(() async {
          if (_bed != null && enabled) await _bedPlayer?.resume();
        }),
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

  void play(Sound sound) {
    if (!_enabled) return;
    played.add(sound.file);
    if (!_real) return;
    final player = _effects[sound] ??= AudioPlayer();
    unawaited(_guard(() async {
      await player.stop();
      await player.play(AssetSource('sounds/${sound.file}.m4a'));
    }));
  }

  /// Cuts a sound short, such as a countdown whose timer ended early.
  void stop(Sound sound) {
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
    if (!_real) return;
    final player = _bedPlayer ??= AudioPlayer();
    unawaited(_guard(() async {
      await player.stop();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('sounds/${bed.file}.m4a'),
          volume: _bedVolume);
    }));
  }

  void _stopBed() {
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
