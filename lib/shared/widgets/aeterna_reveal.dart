import 'dart:async';

import 'package:aeterna/theme/design_tokens.dart';
import 'package:flutter/material.dart';

class AeternaReveal extends StatefulWidget {
  const AeternaReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AeternaTokens.motionDurationNormal,
    this.curve = AeternaTokens.motionCurveStandard,
    this.beginOffset = const Offset(0, 0.04),
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Curve curve;
  final Offset beginOffset;

  @override
  State<AeternaReveal> createState() => _AeternaRevealState();
}

class _AeternaRevealState extends State<AeternaReveal> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.delay > Duration.zero) {
        await Future<void>.delayed(widget.delay);
      }
      if (!mounted) {
        return;
      }
      setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: widget.duration,
      curve: widget.curve,
      opacity: _visible ? 1 : 0,
      child: AnimatedSlide(
        duration: widget.duration,
        curve: widget.curve,
        offset: _visible ? Offset.zero : widget.beginOffset,
        child: widget.child,
      ),
    );
  }
}
