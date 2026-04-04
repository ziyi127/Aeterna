import 'package:aeterna/core/resilience/circuit_breaker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opens after repeated failures and recovers after cooldown', () async {
    final breaker = CircuitBreaker(
      failureThreshold: 2,
      recoveryTimeout: const Duration(milliseconds: 20),
      name: 'test-breaker',
    );

    await expectLater(
      breaker.run<int>(() async => throw StateError('first failure')),
      throwsA(isA<StateError>()),
    );
    expect(breaker.isOpen, isFalse);

    await expectLater(
      breaker.run<int>(() async => throw StateError('second failure')),
      throwsA(isA<StateError>()),
    );
    expect(breaker.isOpen, isTrue);

    await expectLater(
      breaker.run<int>(() async => 1),
      throwsA(isA<CircuitBreakerOpenException>()),
    );

    await Future<void>.delayed(const Duration(milliseconds: 25));

    final result = await breaker.run<int>(() async => 42);
    expect(result, 42);
    expect(breaker.isOpen, isFalse);
    expect(breaker.failureCount, 0);
  });

  test('runOrNull returns null while open', () async {
    final breaker = CircuitBreaker(
      failureThreshold: 1,
      recoveryTimeout: const Duration(milliseconds: 50),
      name: 'test-breaker-open',
    );

    await expectLater(
      breaker.run<void>(() async => throw StateError('boom')),
      throwsA(isA<StateError>()),
    );

    final value = await breaker.runOrNull<int>(() async => 7);
    expect(value, isNull);
  });
}
