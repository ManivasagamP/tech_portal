import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// How the model gets placed (docs/ar-setup-and-gamma-parity.md §2.9, AR-54).
/// The wire name is what `/ar/session?method=` carries.
enum ArPlaceMethod {
  board('board'),
  corners('corners'),
  grid('grid'),
  resume('resume'),
  gnss('gnss');

  const ArPlaceMethod(this.wire);
  final String wire;

  static ArPlaceMethod? parse(String? wire) {
    for (final m in values) {
      if (m.wire == wire) return m;
    }
    return null;
  }
}

class ArPrefsState {
  const ArPrefsState({this.demo = false, this.methodByFloor = const {}, this.loaded = false});

  /// Demo mode: sample building + FakeArEngine, with a visible banner.
  final bool demo;

  /// "Remember my choice for Level 3" — the chooser is skipped next time.
  final Map<String, ArPlaceMethod> methodByFloor;
  final bool loaded;

  ArPrefsState copyWith({bool? demo, Map<String, ArPlaceMethod>? methodByFloor, bool? loaded}) => ArPrefsState(
    demo: demo ?? this.demo,
    methodByFloor: methodByFloor ?? this.methodByFloor,
    loaded: loaded ?? this.loaded,
  );
}

/// Per-device AR preferences in the offline DB's `ar_prefs` table (schema
/// v10, [ArPackStore]), so they survive restarts and are wiped with the rest
/// of the device state on logout. The method key is the one
/// `ArRepository.rememberMethod` uses (`method:<floorId>`), so both agree.
///
/// The remembered method is stored per floor on purpose: a plant room with
/// two boards wants "scan", the open-plan floor above wants "corners".
class ArPrefsController extends Notifier<ArPrefsState> {
  static const _demoKey = 'demo';
  static const _methodPrefix = 'method:';

  final _restored = Completer<void>();

  /// Completes once the saved Demo flag is read — a session must not start
  /// "live" in the moment before a saved "Demo on" arrives.
  Future<void> get ready => _restored.future;

  @override
  ArPrefsState build() {
    unawaited(_restore());
    return const ArPrefsState();
  }

  Future<void> _restore() async {
    try {
      final demo = await ref.read(arPackStoreProvider).getArPref(_demoKey);
      state = state.copyWith(demo: demo == '1', loaded: true);
    } catch (_) {
      // No DB (a widget test) — defaults are fine.
      state = state.copyWith(loaded: true);
    } finally {
      if (!_restored.isCompleted) _restored.complete();
    }
  }

  Future<void> setDemo(bool on) async {
    state = state.copyWith(demo: on);
    try {
      await ref.read(arPackStoreProvider).setArPref(_demoKey, on ? '1' : '0');
    } catch (_) {
      // Best effort: the toggle still works for this run.
    }
  }

  /// The remembered method for [floorId], reading through to the DB once.
  Future<ArPlaceMethod?> rememberedMethod(String floorId) async {
    final cached = state.methodByFloor[floorId];
    if (cached != null) return cached;
    try {
      final raw = await ref.read(arPackStoreProvider).getArPref('$_methodPrefix$floorId');
      final method = ArPlaceMethod.parse(raw);
      if (method != null) {
        state = state.copyWith(methodByFloor: {...state.methodByFloor, floorId: method});
      }
      return method;
    } catch (_) {
      return null;
    }
  }

  /// [method] null forgets the choice ("ask me next time").
  Future<void> rememberMethod(String floorId, ArPlaceMethod? method) async {
    final next = {...state.methodByFloor};
    if (method == null) {
      next.remove(floorId);
    } else {
      next[floorId] = method;
    }
    state = state.copyWith(methodByFloor: next);
    try {
      await ref.read(arPackStoreProvider).setArPref('$_methodPrefix$floorId', method?.wire);
    } catch (_) {
      // Best effort.
    }
  }
}

final arPrefsProvider = NotifierProvider<ArPrefsController, ArPrefsState>(ArPrefsController.new);
