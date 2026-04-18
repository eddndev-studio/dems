import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Fade + translate-up entry animation with optional delay.
/// Never let content appear statically — this sits on top of any first-render
/// node to give it mass and rhythm.
class StaggerReveal extends StatefulWidget {
  const StaggerReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotion.slow,
    this.translateY = 28,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double translateY;

  @override
  State<StaggerReveal> createState() => _StaggerRevealState();
}

class _StaggerRevealState extends State<StaggerReveal> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _visible ? Offset.zero : Offset(0, widget.translateY / 100),
      duration: widget.duration,
      curve: AppMotion.entry,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: widget.duration,
        curve: AppMotion.entry,
        child: widget.child,
      ),
    );
  }
}
