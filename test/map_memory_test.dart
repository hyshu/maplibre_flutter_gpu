import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/memory/map_memory_controller.dart';
import 'package:maplibre_flutter_gpu/src/memory/map_memory_policy.dart';

const mib = 1024 * 1024;
const gib = 1024 * mib;

void main() {
  test('device tiers bound native and GPU retention independently', () {
    final low = MapMemoryBudget.forDevice(physicalBytes: 2 * gib, mobile: true);
    final phone = MapMemoryBudget.forDevice(
      physicalBytes: 8 * gib,
      mobile: true,
    );
    final desktop = MapMemoryBudget.forDevice(
      physicalBytes: 16 * gib,
      mobile: false,
    );
    final unknown = MapMemoryBudget.forDevice(physicalBytes: 0, mobile: false);
    expect(low.nativeTileCount, 4);
    expect(phone.nativeTileCount, 12);
    expect(desktop.nativeTileCount, 24);
    expect(unknown.nativeTileCount, low.nativeTileCount);
    expect(low.gpu.fillExtrusionMaxBytes, 32 * mib);
    expect(phone.gpu.fillExtrusionMaxBytes, 64 * mib);
    expect(desktop.gpu.fillExtrusionMaxBytes, 96 * mib);
    for (final budget in [low, phone, desktop, unknown]) {
      budget.gpu.validate();
      expect(budget.processLimitBytes, lessThan(2 * gib));
    }
  });

  test('warnings disable unused native tiles and quarter GPU budgets', () {
    final base = MapMemoryBudget.forDevice(
      physicalBytes: 4 * gib,
      mobile: true,
    );
    final policy = MapMemoryPolicy(base);
    final decision = policy.evaluate(
      const MapMemorySnapshot(),
      elapsed: Duration.zero,
      warning: true,
    );
    expect(decision.trim, isTrue);
    expect(decision.changed, isTrue);
    expect(decision.budget.nativeTileCount, 0);
    expect(decision.budget.gpu.regularMaxBytes, base.gpu.regularMaxBytes ~/ 4);
    expect(decision.budget.customizerBytes, base.customizerBytes ~/ 4);
  });

  test('low headroom triggers reclamation before the process limit', () {
    final base = MapMemoryBudget.forDevice(
      physicalBytes: 4 * gib,
      mobile: true,
    );
    final policy = MapMemoryPolicy(base);
    final decision = policy.evaluate(
      MapMemorySnapshot(
        availableBytes: base.reserveBytes - 1,
        usageBytes: 100 * mib,
      ),
      elapsed: Duration.zero,
    );
    expect(decision.trim, isTrue);
    expect(decision.budget.nativeTileCount, base.nativeTileCount ~/ 2);
    final critical = policy.evaluate(
      MapMemorySnapshot(availableBytes: base.reserveBytes ~/ 2 - 1),
      elapsed: const Duration(seconds: 5),
    );
    expect(critical.budget.nativeTileCount, 0);
  });

  test('process limit triggers even with ample system memory', () {
    final base = MapMemoryBudget.forDevice(
      physicalBytes: 16 * gib,
      mobile: false,
    );
    final policy = MapMemoryPolicy(base);
    final snapshot = MapMemorySnapshot(
      availableBytes: 8 * gib,
      usageBytes: base.processLimitBytes,
    );
    expect(policy.evaluate(snapshot, elapsed: Duration.zero).trim, isTrue);
    final repeated = policy.evaluate(
      snapshot,
      elapsed: const Duration(seconds: 5),
    );
    expect(repeated.trim, isFalse);
    expect(repeated.changed, isFalse);
  });

  test('healthy readings restore one level at a time after cooldown', () {
    final base = MapMemoryBudget.forDevice(
      physicalBytes: 4 * gib,
      mobile: true,
    );
    final policy = MapMemoryPolicy(base);
    policy.evaluate(
      const MapMemorySnapshot(),
      elapsed: Duration.zero,
      warning: true,
    );
    const healthy = MapMemorySnapshot(
      availableBytes: gib,
      usageBytes: 100 * mib,
    );
    expect(
      policy.evaluate(healthy, elapsed: const Duration(seconds: 5)).changed,
      isFalse,
    );
    expect(
      policy.evaluate(healthy, elapsed: const Duration(seconds: 59)).changed,
      isFalse,
    );
    final reduced = policy.evaluate(
      healthy,
      elapsed: const Duration(seconds: 60),
    );
    expect(reduced.budget.nativeTileCount, base.nativeTileCount ~/ 2);
    expect(reduced.trim, isFalse);
    expect(
      policy.evaluate(healthy, elapsed: const Duration(seconds: 119)).changed,
      isFalse,
    );
    expect(
      policy
          .evaluate(healthy, elapsed: const Duration(seconds: 120))
          .budget
          .nativeTileCount,
      base.nativeTileCount,
    );
  });

  test('unknown readings cannot restore budgets after a warning', () {
    final policy = MapMemoryPolicy(
      MapMemoryBudget.forDevice(physicalBytes: 0, mobile: true),
    );
    policy.evaluate(
      const MapMemorySnapshot(),
      elapsed: Duration.zero,
      warning: true,
    );
    final decision = policy.evaluate(
      const MapMemorySnapshot(),
      elapsed: const Duration(minutes: 10),
    );
    expect(decision.budget.nativeTileCount, 0);
    expect(decision.changed, isFalse);
  });

  test(
    'warnings wait for a frame lease before touching either cache',
    () async {
      final barrier = Completer<void>();
      final events = <String>[];
      final controller = memoryController(
        beforeMutation: () {
          events.add('lease');

          return barrier.future;
        },
        applyBudget: (_) => events.add('budget'),
        trimCaches: () => events.add('native+gpu'),
      );
      final check = controller.check(warning: true);
      expect(events, ['lease']);
      barrier.complete();
      await check;
      expect(events, ['lease', 'budget', 'native+gpu']);
      controller.dispose();
    },
  );

  test('disposal during a frame lease prevents native and GPU calls', () async {
    final barrier = Completer<void>();
    var calls = 0;
    final controller = memoryController(
      beforeMutation: () => barrier.future,
      applyBudget: (_) => calls++,
      trimCaches: () => calls++,
    );
    final check = controller.check(warning: true);
    controller.dispose();
    barrier.complete();
    await check;
    expect(calls, 0);
  });

  test('a warning arriving during another check is not dropped', () async {
    final barrier = Completer<void>();
    var trimmed = 0;
    final budgets = <int>[];
    final controller = memoryController(
      beforeMutation: () => barrier.future,
      applyBudget: (budget) => budgets.add(budget.nativeTileCount),
      trimCaches: () => trimmed++,
    );
    final check = controller.check();
    await controller.check(warning: true);
    barrier.complete();
    await check;
    expect(budgets, [8, 0]);
    expect(trimmed, 1);
    controller.dispose();
  });

  test(
    'measurement failures do not prevent warning-driven reclamation',
    () async {
      var trimmed = 0;
      var errors = 0;
      final controller = memoryController(
        readSnapshot: () => throw StateError('unavailable'),
        trimCaches: () => trimmed++,
        onError: (_, _) => errors++,
      );
      await controller.check(warning: true);
      expect(trimmed, 1);
      expect(errors, 1);
      controller.dispose();
    },
  );

  test('failed reclamation retries on the next check', () async {
    var tries = 0;
    var errors = 0;
    final controller = memoryController(
      trimCaches: () {
        if (++tries == 1) throw StateError('retry');
      },
      onError: (_, _) => errors++,
    );
    await controller.check(warning: true);
    await controller.check();
    expect(tries, 2);
    expect(errors, 1);
    controller.dispose();
  });
}

MapMemoryController memoryController({
  MapMemorySnapshot Function()? readSnapshot,
  Future<void> Function()? beforeMutation,
  void Function(MapMemoryBudget)? applyBudget,
  void Function()? trimCaches,
  void Function(Object, StackTrace)? onError,
}) => MapMemoryController(
  policy: MapMemoryPolicy(
    MapMemoryBudget.forDevice(physicalBytes: 4 * gib, mobile: true),
  ),
  readSnapshot: readSnapshot ?? () => const MapMemorySnapshot(),
  beforeMutation: beforeMutation ?? () async {},
  applyBudget: applyBudget ?? (_) {},
  trimCaches: trimCaches ?? () {},
  isActive: () => true,
  onError: onError ?? (error, _) => fail('$error'),
);
