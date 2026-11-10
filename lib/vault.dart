import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart' as pc;

class Wallet {
  final String id;
  final String name;
  final String mnemonic;

  const Wallet({required this.id, required this.name, required this.mnemonic});

  Wallet copyWith({String? name}) =>
      Wallet(id: id, name: name ?? this.name, mnemonic: mnemonic);

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'mnemonic': mnemonic};

  factory Wallet.fromJson(Map<String, dynamic> j) => Wallet(
        id: j['id'] as String,
        name: j['name'] as String,
        mnemonic: j['mnemonic'] as String,
      );
}

/// PIN ve cuzdanlari Android Keystore destekli sifreli depoda tutar.
class Vault {
  static const _storage = FlutterSecureStorage();
  static const _kPinHash = 'pin_hash';
  static const _kPinSalt = 'pin_salt';
  static const _kWallets = 'wallets';
  static const _kSelected = 'selected_wallet';
  static const _kCurrency = 'currency';
  static const _kPinV = 'pin_v';
  static const _kLockDelay = 'lock_delay';
  static const _kBio = 'biometric';
  static const _kSecure = 'secure_screen';
  static const _kFails = 'pin_fails';
  static const _kLockUntil = 'pin_lock_until';

  // Eski surum (v1): tek SHA-256. Sadece gecis icin tutuluyor.
  static String _hashV1(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  // Yeni surum (v2): PBKDF2-HMAC-SHA256, 20.000 tur.
  static String _hashV2(String salt, String pin) {
    final kd = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(
        Uint8List.fromList(utf8.encode(salt)),
        20000,
        32,
      ));
    return base64Url.encode(kd.process(Uint8List.fromList(utf8.encode(pin))));
  }

  /// Zamanlama saldirisina karsi sabit zamanli karsilastirma.
  static bool _eq(String a, String b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return r == 0;
  }

  static Future<bool> hasPin() async =>
      (await _storage.read(key: _kPinHash)) != null;

  static Future<void> setPin(String pin) async {
    final rnd = Random.secure();
    final salt =
        base64Url.encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    await _storage.write(key: _kPinSalt, value: salt);
    await _storage.write(key: _kPinHash, value: _hashV2(salt, pin));
    await _storage.write(key: _kPinV, value: '2');
  }

  /// Kilit suresi bittiyse 0, bitmediyse kalan saniye.
  /// Uygulama kapatilip acilsa da sifirlanmaz.
  static Future<int> lockRemaining() async {
    final until =
        int.tryParse(await _storage.read(key: _kLockUntil) ?? '') ?? 0;
    final ms = until - DateTime.now().millisecondsSinceEpoch;
    return ms > 0 ? (ms / 1000).ceil() : 0;
  }

  static Future<void> _registerFail() async {
    final fails =
        (int.tryParse(await _storage.read(key: _kFails) ?? '') ?? 0) + 1;
    await _storage.write(key: _kFails, value: '$fails');
    if (fails >= 5) {
      // 5. hatada 30 sn, sonra her hatada iki kati; en fazla 1 saat.
      final sec = min(3600, 30 * pow(2, fails - 5).toInt());
      final until = DateTime.now().millisecondsSinceEpoch + sec * 1000;
      await _storage.write(key: _kLockUntil, value: '$until');
    }
  }

  static Future<void> _resetFails() async {
    await _storage.delete(key: _kFails);
    await _storage.delete(key: _kLockUntil);
  }

  static Future<bool> verifyPin(String pin) async {
    if (await lockRemaining() > 0) return false;
    final salt = await _storage.read(key: _kPinSalt);
    final stored = await _storage.read(key: _kPinHash);
    if (salt == null || stored == null) return false;
    final v = await _storage.read(key: _kPinV);
    bool ok;
    if (v == '2') {
      ok = _eq(_hashV2(salt, pin), stored);
    } else {
      ok = _eq(_hashV1(salt, pin), stored);
      if (ok) await setPin(pin); // eski kaydi guclu yonteme tasi
    }
    if (ok) {
      await _resetFails();
    } else {
      await _registerFail();
    }
    return ok;
  }

  // ---- Guvenlik ayarlari ----
  static Future<int> getLockDelay() async =>
      int.tryParse(await _storage.read(key: _kLockDelay) ?? '') ?? 30;
  static Future<void> setLockDelay(int sec) =>
      _storage.write(key: _kLockDelay, value: '$sec');

  static Future<bool> getBio() async =>
      (await _storage.read(key: _kBio)) == '1';
  static Future<void> setBio(bool on) =>
      _storage.write(key: _kBio, value: on ? '1' : '0');

  static Future<bool> getSecure() async =>
      (await _storage.read(key: _kSecure)) != '0';
  static Future<void> setSecure(bool on) =>
      _storage.write(key: _kSecure, value: on ? '1' : '0');

  /// Ayni ad (buyuk/kucuk harf ve bosluk fark etmez) baska cuzdanda var mi?
  static bool nameTaken(List<Wallet> wallets, String name, {String? exceptId}) {
    final n = name.trim().toLowerCase();
    return wallets.any((w) => w.id != exceptId && w.name.trim().toLowerCase() == n);
  }

  static Future<List<Wallet>> loadWallets() async {
    final raw = await _storage.read(key: _kWallets);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Wallet.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveWallets(List<Wallet> wallets) async {
    await _storage.write(
      key: _kWallets,
      value: jsonEncode(wallets.map((w) => w.toJson()).toList()),
    );
  }

  static Future<String?> getSelected() => _storage.read(key: _kSelected);

  static Future<void> setSelected(String id) =>
      _storage.write(key: _kSelected, value: id);

  static Future<String> getCurrency() async =>
      (await _storage.read(key: _kCurrency)) ?? 'usd';

  static Future<void> setCurrency(String c) =>
      _storage.write(key: _kCurrency, value: c);

  static String newId() {
    final rnd = Random.secure();
    return List<int>.generate(8, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
