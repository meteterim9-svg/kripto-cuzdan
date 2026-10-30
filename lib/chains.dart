import 'dart:convert';
import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

/// Bir seed'den turetilen, her ag icin ana adresler.
class ChainAddresses {
  final String btc;
  final String eth;
  final String trx;
  const ChainAddresses({required this.btc, required this.eth, required this.trx});
}

Uint8List _sha256(List<int> d) =>
    Uint8List.fromList(crypto.sha256.convert(d).bytes);

Uint8List _ripemd160(Uint8List d) => RIPEMD160Digest().process(d);

Uint8List _keccak256(Uint8List d) => KeccakDigest(256).process(d);

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

// ---------- Base58Check (Tron) ----------

const _b58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

String _base58(Uint8List input) {
  var zeros = 0;
  while (zeros < input.length && input[zeros] == 0) {
    zeros++;
  }
  var num = BigInt.zero;
  for (final b in input) {
    num = (num << 8) | BigInt.from(b);
  }
  final base = BigInt.from(58);
  final chars = <String>[];
  while (num > BigInt.zero) {
    chars.add(_b58[(num % base).toInt()]);
    num = num ~/ base;
  }
  return '1' * zeros + chars.reversed.join();
}

String _base58Check(Uint8List payload) {
  final checksum = _sha256(_sha256(payload)).sublist(0, 4);
  return _base58(Uint8List.fromList([...payload, ...checksum]));
}

// ---------- Bech32 (Bitcoin native segwit) ----------

const _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

int _polymod(List<int> values) {
  const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
  var chk = 1;
  for (final v in values) {
    final top = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    for (var i = 0; i < 5; i++) {
      if (((top >> i) & 1) == 1) chk ^= gen[i];
    }
  }
  return chk;
}

List<int> _hrpExpand(String hrp) => [
      ...hrp.codeUnits.map((c) => c >> 5),
      0,
      ...hrp.codeUnits.map((c) => c & 31),
    ];

List<int> _convertBits(List<int> data, int from, int to, bool pad) {
  var acc = 0;
  var bits = 0;
  final ret = <int>[];
  final maxv = (1 << to) - 1;
  final maxAcc = (1 << (from + to - 1)) - 1;
  for (final v in data) {
    acc = ((acc << from) | v) & maxAcc;
    bits += from;
    while (bits >= to) {
      bits -= to;
      ret.add((acc >> bits) & maxv);
    }
  }
  if (pad && bits > 0) {
    ret.add((acc << (to - bits)) & maxv);
  }
  return ret;
}

String _segwitV0Address(String hrp, Uint8List program) {
  final data = [0, ..._convertBits(program, 8, 5, true)];
  final values = [..._hrpExpand(hrp), ...data, 0, 0, 0, 0, 0, 0];
  final mod = _polymod(values) ^ 1;
  final checksum = List<int>.generate(6, (i) => (mod >> (5 * (5 - i))) & 31);
  return '${hrp}1${[...data, ...checksum].map((d) => _charset[d]).join()}';
}

// ---------- Turetme ----------

Uint8List _uncompressed(Uint8List compressed) {
  final curve = ECCurve_secp256k1();
  final point = curve.curve.decodePoint(compressed)!;
  return point.getEncoded(false);
}

/// 20 baytlik ETH/TRX adres govdesi: keccak256(pubkey[1:])[12:]
Uint8List _evmHash(Uint8List compressedPub) {
  final pub = _uncompressed(compressedPub);
  return _keccak256(pub.sublist(1)).sublist(12);
}

String _eip55(Uint8List addr20) {
  final lower = _hex(addr20);
  final hash = _hex(_keccak256(Uint8List.fromList(utf8.encode(lower))));
  final sb = StringBuffer('0x');
  for (var i = 0; i < lower.length; i++) {
    final c = lower[i];
    final nibble = int.parse(hash[i], radix: 16);
    sb.write(nibble >= 8 ? c.toUpperCase() : c);
  }
  return sb.toString();
}

/// Seed kelimelerinden (BIP39) BTC (BIP84), ETH (BIP44, 60) ve
/// TRX (BIP44, 195) ana adreslerini uretir.
ChainAddresses addressesFor(String mnemonic) {
  final seed = bip39.mnemonicToSeed(mnemonic);
  final root = bip32.BIP32.fromSeed(seed);

  final btcNode = root.derivePath("m/84'/0'/0'/0/0");
  final h160 = _ripemd160(_sha256(btcNode.publicKey));
  final btc = _segwitV0Address('bc', h160);

  final ethNode = root.derivePath("m/44'/60'/0'/0/0");
  final eth = _eip55(_evmHash(ethNode.publicKey));

  final trxNode = root.derivePath("m/44'/195'/0'/0/0");
  final trx = _base58Check(
    Uint8List.fromList([0x41, ..._evmHash(trxNode.publicKey)]),
  );

  return ChainAddresses(btc: btc, eth: eth, trx: trx);
}
