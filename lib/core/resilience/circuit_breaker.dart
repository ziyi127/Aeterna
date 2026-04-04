import 'dart:async';

enum CircuitBreakerState { closed, open, halfOpen }

class CircuitBreakerOpenException implements Exception {
  // Thrown when a caller tries to run work while the breaker is open.
  CircuitBreakerOpenException(this.message);

  final String message;

  @override
  String toString() => 'CircuitBreakerOpenException: $message';
}

class CircuitBreaker {
  // The breaker prevents repeated failing operations from running forever.
  CircuitBreaker({
    required this.failureThreshold,
    required this.recoveryTimeout,
    this.onStateChanged,
    this.name = 'circuit-breaker',
  }) : assert(failureThreshold > 0);

  final int failureThreshold;
  final Duration recoveryTimeout;
  final String name;
  final void Function(CircuitBreakerState previous, CircuitBreakerState next)?
  onStateChanged;

  CircuitBreakerState _state = CircuitBreakerState.closed;
  int _failureCount = 0;
  DateTime? _openedAt;

  CircuitBreakerState get state => _state;

  bool get isOpen => _state == CircuitBreakerState.open;

  bool get isHalfOpen => _state == CircuitBreakerState.halfOpen;

  int get failureCount => _failureCount;

  Future<T> run<T>(Future<T> Function() action) async {
    // Refuse work immediately when the breaker has not cooled down yet.
    if (!_canAttempt()) {
      throw CircuitBreakerOpenException(
        '$name is open; retry after ${recoveryTimeout.inMilliseconds}ms',
      );
    }

    if (_state == CircuitBreakerState.open) {
      _transitionTo(CircuitBreakerState.halfOpen);
    }

    try {
      final result = await action();
      _markSuccess();
      return result;
    } catch (_) {
      _markFailure();
      rethrow;
    }
  }

  Future<T?> runOrNull<T>(Future<T> Function() action) async {
    // Convenience wrapper for callers that only care about best-effort work.
    try {
      return await run(action);
    } on CircuitBreakerOpenException {
      return null;
    } catch (_) {
      return null;
    }
  }

  void reset() {
    // Reset is used when the caller knows the underlying problem is gone.
    _failureCount = 0;
    _openedAt = null;
    _transitionTo(CircuitBreakerState.closed);
  }

  bool _canAttempt() {
    // Open breakers may re-enter half-open mode once the timeout has elapsed.
    if (_state != CircuitBreakerState.open) {
      return true;
    }

    final openedAt = _openedAt;
    if (openedAt == null) {
      return true;
    }

    final elapsed = DateTime.now().difference(openedAt);
    if (elapsed >= recoveryTimeout) {
      _transitionTo(CircuitBreakerState.halfOpen);
      return true;
    }

    return false;
  }

  void _markSuccess() {
    // Any successful attempt should close the breaker and clear failure history.
    _failureCount = 0;
    _openedAt = null;
    if (_state != CircuitBreakerState.closed) {
      _transitionTo(CircuitBreakerState.closed);
    }
  }

  void _markFailure() {
    // Count failures until the threshold is reached, then open the breaker.
    _failureCount++;
    if (_failureCount >= failureThreshold) {
      _openedAt = DateTime.now();
      _transitionTo(CircuitBreakerState.open);
    } else {
      _transitionTo(CircuitBreakerState.closed);
    }
  }

  void _transitionTo(CircuitBreakerState next) {
    // State transitions are centralized so observers see every change consistently.
    if (_state == next) {
      return;
    }
    final previous = _state;
    _state = next;
    onStateChanged?.call(previous, next);
  }
}
