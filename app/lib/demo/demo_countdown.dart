import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/game_ui.dart';

/// Prototype-only countdown that starts from a fixed number of seconds on the
/// device and calls [onDone] at zero so the click-through can move on.
///
/// Not the real timer: in the connected app every phase counts down to the
/// server's `deadline` (docs/protocol.md), and only the server advances the
/// game. Replace uses of this widget with a [TimerBadge] driven by that
/// deadline when the client is wired to the server.
class DemoCountdown extends StatefulWidget {
  const DemoCountdown({required this.seconds, this.onDone, super.key});

  final int seconds;
  final VoidCallback? onDone;

  @override
  State<DemoCountdown> createState() => _DemoCountdownState();
}

class _DemoCountdownState extends State<DemoCountdown> {
  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _left--);
      if (_left > 0) return;
      timer.cancel();
      // The screen may already be leaving because the player acted first.
      if (ModalRoute.of(context)?.isCurrent ?? true) widget.onDone?.call();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TimerBadge(seconds: _left);
}
