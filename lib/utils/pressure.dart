import 'dart:math' as math;

import 'package:flutter/gestures.dart';

/// Converts raw pointer pressure into a normalised 0..1 value.
///
/// This is one of the trickier parts of a cross-platform drawing app, because
/// input devices disagree:
///
///  * A stylus (Apple Pencil, S Pen, Wacom) reports a real analogue pressure
///    between [PointerEvent.pressureMin] and [PointerEvent.pressureMax].
///  * A finger on a touch screen usually reports a constant value, so
///    `pressureMin == pressureMax` and the ratio is meaningless.
///  * A mouse or trackpad reports no pressure at all.
///
/// When real pressure is unavailable the normaliser falls back to *simulated*
/// pressure derived from pointer speed: slow, deliberate movement produces a
/// thick stroke and fast movement thins out, which is how a real pen behaves.
/// The result is smoothed so the stroke width never jumps between samples.
class PressureNormaliser {
  PressureNormaliser({
    this.smoothing = 0.35,
    this.speedForMinPressure = 2200.0,
    this.simulatedFloor = 0.25,
  });

  /// 0 = no smoothing (raw values), 1 = never change. 0.3-0.4 feels natural.
  final double smoothing;

  /// Pointer speed (logical px/s) at which simulated pressure bottoms out.
  final double speedForMinPressure;

  /// Lowest simulated pressure, so fast strokes still leave a visible mark.
  final double simulatedFloor;

  double _last = 0.5;
  Offset? _lastPosition;
  Duration? _lastTimestamp;
  bool _deviceSupportsPressure = false;

  /// True when the current pointer actually reported analogue pressure.
  /// The UI surfaces this so the user knows whether their stylus is working.
  bool get deviceSupportsPressure => _deviceSupportsPressure;

  /// Call at pointer-down to reset per-stroke state.
  void begin(PointerDownEvent event) {
    _deviceSupportsPressure = _hasRealPressure(event);
    _lastPosition = event.localPosition;
    _lastTimestamp = event.timeStamp;
    _last = _deviceSupportsPressure ? _raw(event) : 0.5;
  }

  /// Call for every move event; returns the pressure to store on the point.
  double update(PointerEvent event) {
    final double target;
    if (_deviceSupportsPressure || _hasRealPressure(event)) {
      _deviceSupportsPressure = true;
      target = _raw(event);
    } else {
      target = _simulateFromSpeed(event);
    }
    _lastPosition = event.localPosition;
    _lastTimestamp = event.timeStamp;
    _last = _last + (target - _last) * (1.0 - smoothing);
    return _last.clamp(0.0, 1.0);
  }

  /// Pressure for the very first point of a stroke.
  double get current => _last.clamp(0.0, 1.0);

  void end() {
    _lastPosition = null;
    _lastTimestamp = null;
  }

  static bool _hasRealPressure(PointerEvent event) {
    final range = event.pressureMax - event.pressureMin;
    return range > 0.01 && event.kind == PointerDeviceKind.stylus;
  }

  static double _raw(PointerEvent event) {
    final range = event.pressureMax - event.pressureMin;
    if (range <= 0.01) return 0.5;
    return ((event.pressure - event.pressureMin) / range).clamp(0.0, 1.0);
  }

  double _simulateFromSpeed(PointerEvent event) {
    final lastPosition = _lastPosition;
    final lastTimestamp = _lastTimestamp;
    if (lastPosition == null || lastTimestamp == null) return 0.5;

    final dtMicros = (event.timeStamp - lastTimestamp).inMicroseconds;
    if (dtMicros <= 0) return _last;

    final distance = (event.localPosition - lastPosition).distance;
    final speed = distance / (dtMicros / 1000000.0);
    final t = (speed / speedForMinPressure).clamp(0.0, 1.0);
    // Ease the curve so small speed changes near zero matter less.
    final eased = math.pow(t, 0.7).toDouble();
    return simulatedFloor + (1.0 - simulatedFloor) * (1.0 - eased);
  }
}
