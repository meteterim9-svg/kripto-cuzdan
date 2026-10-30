import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  static String _hash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static Future<bool> hasPin() async =>
      (await _storage.read(key: _kPinHash)) != null;

  static Future<void> setPin(String pin) async {
    final rnd = Random.secure();
    final salt = base64Url.encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    await _storage.write(key: _kPinSalt, value: salt);
    await _storage.write(key: _kPinHash, value: _hash(salt, pin));
  }

  static Future<bool> verifyPin(String pin) async {
    final salt = await _storage.read(key: _kPinSalt);
    final stored = await _storage.read(key: _kPinHash);
    if (salt == null || stored == null) return false;
    return _hash(salt, pin) == stored;
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
