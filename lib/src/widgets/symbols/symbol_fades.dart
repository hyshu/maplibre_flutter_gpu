part of 'symbol_overlay.dart';

class _BatchedSymbolFadeController extends ChangeNotifier {
  new({required TickerProvider vsync, required this.onFadedOut}) {
    _ticker = vsync.createTicker(_handleTick);
  }

  final void Function(String key) onFadedOut;
  late final Ticker _ticker;
  final Map<Object, _BatchedSymbolFade> _fades = {};
  Duration _timeline = Duration.zero;
  Duration _tickerBase = Duration.zero;
  bool _disposed = false;

  double opacityFor(Object id) => _fades[id]?.opacity ?? 1;

  bool isVisible(Object id) => _fades[id]?.visible ?? false;

  void update(List<_SymbolPaintItem> items, Duration duration) {
    final liveIds = {for (final item in items) item.id};
    var changed = false;
    _fades.removeWhere((id, _) {
      final removes = !liveIds.contains(id);
      if (removes) changed = true;

      return removes;
    });
    for (final item in items) {
      final existing = _fades[item.id];
      if (existing == null) {
        final startsVisible = item.visible && !item.fadeIn;
        final fade = _BatchedSymbolFade(
          symbolKey: item.symbolKey,
          visible: item.visible,
          opacity: startsVisible ? 1 : 0,
          from: startsVisible ? 1 : 0,
          target: item.visible ? 1 : 0,
          startedAt: _timeline,
          duration: duration,
        );
        _fades[item.id] = fade;
        changed = true;
        if (fade.opacity != fade.target && duration > Duration.zero) {
          fade.animating = true;
        } else {
          fade.opacity = fade.target;
          if (!item.visible) _scheduleFadeCompletion(item.id, fade);
        }
        continue;
      }
      existing.symbolKey = item.symbolKey;
      if (existing.visible != item.visible) {
        _startTransition(item.id, existing, item.visible, duration);
        changed = true;
      } else if (existing.animating && existing.duration != duration) {
        existing
          ..from = existing.opacity
          ..startedAt = _timeline
          ..duration = duration;
        if (duration == Duration.zero) {
          existing
            ..opacity = existing.target
            ..animating = false;
          if (!existing.visible) {
            _scheduleFadeCompletion(item.id, existing);
          }
        }
        changed = true;
      }
    }
    if (_fades.values.any((fade) => fade.animating)) {
      _ensureTicking();
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
    if (changed) notifyListeners();
  }

  void _startTransition(
    Object id,
    _BatchedSymbolFade fade,
    bool visible,
    Duration duration,
  ) {
    fade
      ..visible = visible
      ..from = fade.opacity
      ..target = visible ? 1 : 0
      ..startedAt = _timeline
      ..duration = duration
      ..generation = fade.generation + 1
      ..completionScheduled = false
      ..animating =
          fade.opacity != (visible ? 1 : 0) && duration > Duration.zero;
    if (!fade.animating) {
      fade.opacity = fade.target;
      if (!visible) _scheduleFadeCompletion(id, fade);
    }
  }

  void _ensureTicking() {
    if (_ticker.isActive) return;
    _tickerBase = _timeline;
    _ticker.start();
  }

  void _handleTick(Duration elapsed) {
    _timeline = _tickerBase + elapsed;
    var changed = false;
    for (final entry in _fades.entries) {
      final fade = entry.value;
      if (!fade.animating) continue;
      final durationMicros = fade.duration.inMicroseconds;
      final elapsedMicros = (_timeline - fade.startedAt).inMicroseconds;
      final progress = durationMicros <= 0
          ? 1.0
          : (elapsedMicros / durationMicros).clamp(0.0, 1.0);
      fade.opacity = fade.from + (fade.target - fade.from) * progress;
      changed = true;
      if (progress < 1) continue;
      fade.animating = false;
      if (!fade.visible) _scheduleFadeCompletion(entry.key, fade);
    }
    if (!_fades.values.any((fade) => fade.animating)) _ticker.stop();
    if (changed) notifyListeners();
  }

  void _scheduleFadeCompletion(Object id, _BatchedSymbolFade fade) {
    if (fade.completionScheduled) return;
    fade.completionScheduled = true;
    final generation = fade.generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      final current = _fades[id];
      if (current == null ||
          current.generation != generation ||
          current.visible) {
        return;
      }
      onFadedOut(current.symbolKey);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _fades.clear();
    _ticker.dispose();
    super.dispose();
  }
}

class _BatchedSymbolFade({
  required var String symbolKey,
  required var bool visible,
  required var double opacity,
  required var double from,
  required var double target,
  required var Duration startedAt,
  required var Duration duration,
}) {
  bool animating = false;
  int generation = 0;
  bool completionScheduled = false;
}
