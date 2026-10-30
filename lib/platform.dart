import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Ekran goruntusu/ekran kaydi engeli (Android FLAG_SECURE).
class ScreenSecurity {
  static const _ch = MethodChannel('orvexa/secure');

  static Future<void> set(bool on) async {
    try {
      await _ch.invokeMethod<void>('setSecure', {'on': on});
    } catch (_) {}
  }
}

/// Parmak izi / yuz ile kilit acma.
class Bio {
  static final _auth = LocalAuthentication();

  static Future<bool> available() async {
    try {
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
