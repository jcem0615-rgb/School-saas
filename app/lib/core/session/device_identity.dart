import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Who this installation is, as far as the account is concerned.
///
/// "Device" here means one app installation on one machine, which on the
/// web is one browser profile. That is the honest unit: two browsers on
/// the same laptop are two devices to this app, and there is no way to
/// tell them apart from inside a page without fingerprinting, which this
/// app does not do.
abstract class DeviceIdentity {
  /// A stable id for this installation, or null if it cannot be
  /// remembered.
  ///
  /// Null is not a failure to be papered over with a fresh random id, and
  /// the single-device rule switches itself off when it sees one. A new
  /// id on every launch would read as a new device every launch, so the
  /// account would displace itself and sign the user out roughly as fast
  /// as they could sign in. Somebody in a private window, or with site
  /// data blocked, gets no enforcement rather than an app they cannot
  /// stay signed in to.
  Future<String?> id();

  /// Something a person would recognise on the screen that tells them
  /// they were signed out -- "a web browser", "an Android device".
  /// Coarse on purpose: the point is to say *elsewhere*, not to describe
  /// the other machine.
  String get label;
}

/// The real one: an id minted once and kept in local storage.
class StoredDeviceIdentity implements DeviceIdentity {
  static const _key = 'logicclass.device-id';

  final SharedPreferences Function()? _preloaded;

  String? _cached;

  StoredDeviceIdentity({SharedPreferences Function()? preloaded})
      : _preloaded = preloaded;

  @override
  Future<String?> id() async {
    if (_cached != null) return _cached;
    try {
      final prefs = _preloaded?.call() ?? await SharedPreferences.getInstance();
      final existing = prefs.getString(_key);
      if (existing != null && existing.isNotEmpty) return _cached = existing;

      final minted = _mintId();
      await prefs.setString(_key, minted);
      // Read back rather than trust the write. If storage is full or
      // disabled the set is a no-op that does not throw, and an id we
      // only think we stored is the every-launch-is-a-new-device case
      // this class exists to avoid.
      final stored = prefs.getString(_key);
      if (stored != minted) return null;
      return _cached = minted;
    } catch (_) {
      return null;
    }
  }

  @override
  String get label => deviceLabel();

  /// 128 bits of hex. Not a secret and not a fingerprint -- it identifies
  /// nothing about the machine, only that it is the same one as last
  /// time. Random.secure so two installations do not collide by seeding
  /// themselves off the same clock tick.
  static String _mintId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

/// Shared by the real identity and the tests, so the wording a user is
/// shown is the wording the tests assert on.
String deviceLabel() {
  if (kIsWeb) return 'a web browser';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'an Android device',
    TargetPlatform.iOS => 'an iPhone or iPad',
    TargetPlatform.windows => 'a Windows PC',
    TargetPlatform.macOS => 'a Mac',
    TargetPlatform.linux => 'a Linux PC',
    TargetPlatform.fuchsia => 'another device',
  };
}

/// A fixed identity, for tests and for anywhere the real one would have
/// to touch storage.
class FixedDeviceIdentity implements DeviceIdentity {
  final String? value;
  @override
  final String label;

  const FixedDeviceIdentity(this.value, {this.label = 'a web browser'});

  @override
  Future<String?> id() async => value;
}
