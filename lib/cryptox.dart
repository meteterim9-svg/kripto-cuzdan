import 'dart:typed_data';

import 'package:crypto/crypto.dart' as cr;
import 'package:pointycastle/export.dart';

// ---------------------------------------------------------------
// Temel yardimcilar
// ---------------------------------------------------------------

String toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List fromHex(String h) {
  var s = h.startsWith('0x') ? h.substring(2) : h;
  if (s.length.isOdd) s = '0$s';
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(2 * i, 2 * i + 2), radix: 16);
  }
  return out;
}

Uint8List concat(Iterable<List<int>> parts) {
  final out = <int>[];
  for (final p in parts) {
    out.addAll(p);
  }
  return Uint8List.fromList(out);
}

BigInt bytesToBig(List<int> b) {
  var r = BigInt.zero;
  for (final x in b) {
    r = (r << 8) | BigInt.from(x);
  }
  return r;
}

/// [len] verilirse soldan sifirla doldurur, verilmezse en kisa halini dondurur.
Uint8List bigToBytes(BigInt v, [int? len]) {
  var hex = v == BigInt.zero ? '' : v.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  var b = fromHex(hex);
  if (len != null) {
    if (b.length > len) throw ArgumentError('sayi cok buyuk');
    b = concat([Uint8List(len - b.length), b]);
  }
  return b;
}

Uint8List sha256(List<int> d) => Uint8List.fromList(cr.sha256.convert(d).bytes);
Uint8List dsha256(List<int> d) => sha256(sha256(d));
Uint8List hash160(List<int> d) =>
    RIPEMD160Digest().process(sha256(d));
Uint8List keccak256(List<int> d) =>
    KeccakDigest(256).process(Uint8List.fromList(d));

// ---------------------------------------------------------------
// secp256k1 ECDSA (RFC 6979, dusuk-s)
// ---------------------------------------------------------------

final ECDomainParameters _curve = ECCurve_secp256k1();
final BigInt _n = _curve.n;

class EcSig {
  final BigInt r;
  final BigInt s;
  final int rec; // kurtarma kimligi 0/1
  const EcSig(this.r, this.s, this.rec);
}

Uint8List _hmac(Uint8List key, List<int> data) =>
    Uint8List.fromList(cr.Hmac(cr.sha256, key).convert(data).bytes);

BigInt _rfc6979(BigInt d, Uint8List h) {
  final x = bigToBytes(d, 32);
  final h1 = bigToBytes(bytesToBig(h) % _n, 32);
  var v = Uint8List.fromList(List<int>.filled(32, 1));
  var k = Uint8List(32);
  k = _hmac(k, [...v, 0, ...x, ...h1]);
  v = _hmac(k, v);
  k = _hmac(k, [...v, 1, ...x, ...h1]);
  v = _hmac(k, v);
  while (true) {
    v = _hmac(k, v);
    final cand = bytesToBig(v);
    if (cand >= BigInt.one && cand < _n) return cand;
    k = _hmac(k, [...v, 0]);
    v = _hmac(k, v);
  }
}

Uint8List publicKeyCompressed(Uint8List priv) {
  final q = (_curve.G * bytesToBig(priv))!;
  return q.getEncoded(true);
}

Uint8List publicKeyUncompressed(Uint8List priv) {
  final q = (_curve.G * bytesToBig(priv))!;
  return q.getEncoded(false);
}

/// Ayni ozel anahtardan 20 baytlik EVM/Tron adres govdesi.
Uint8List evmHashFromPriv(Uint8List priv) =>
    keccak256(publicKeyUncompressed(priv).sublist(1)).sublist(12);

EcSig ecdsaSign(Uint8List priv, Uint8List hash) {
  final d = bytesToBig(priv);
  final k = _rfc6979(d, hash);
  final rp = (_curve.G * k)!;
  final rx = rp.x!.toBigInteger()!;
  final ry = rp.y!.toBigInteger()!;
  final r = rx % _n;
  if (r == BigInt.zero) throw StateError('imza uretilemedi');
  var s = (k.modInverse(_n) * (bytesToBig(hash) + r * d)) % _n;
  if (s == BigInt.zero) throw StateError('imza uretilemedi');
  var rec = (ry.isOdd ? 1 : 0) | (rx >= _n ? 2 : 0);
  if (s > (_n >> 1)) {
    s = _n - s;
    rec ^= 1;
  }
  return EcSig(r, s, rec);
}

Uint8List derSig(BigInt r, BigInt s) {
  Uint8List enc(BigInt x) {
    var b = bigToBytes(x);
    if ((b[0] & 0x80) != 0) b = concat([[0], b]);
    return concat([
      [0x02, b.length],
      b,
    ]);
  }

  final body = concat([enc(r), enc(s)]);
  return concat([
    [0x30, body.length],
    body,
  ]);
}

// ---------------------------------------------------------------
// RLP
// ---------------------------------------------------------------

Uint8List _rlpLen(int n, int offset) {
  if (n < 56) return Uint8List.fromList([offset + n]);
  final b = bigToBytes(BigInt.from(n));
  return concat([
    [offset + 55 + b.length],
    b,
  ]);
}

/// Desteklenen girdiler: int, BigInt, Uint8List, List.
Uint8List rlp(dynamic x) {
  if (x is Uint8List) {
    if (x.length == 1 && x[0] < 0x80) return x;
    return concat([_rlpLen(x.length, 0x80), x]);
  }
  if (x is int) return rlp(BigInt.from(x));
  if (x is BigInt) return rlp(bigToBytes(x));
  if (x is List) {
    final body = concat(x.map((e) => rlp(e)));
    return concat([_rlpLen(body.length, 0xc0), body]);
  }
  throw ArgumentError('rlp: desteklenmeyen tur');
}

// ---------------------------------------------------------------
// Base58Check ve Bech32 (cozme)
// ---------------------------------------------------------------

const _b58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

Uint8List? base58Decode(String s) {
  var n = BigInt.zero;
  final base = BigInt.from(58);
  for (final ch in s.split('')) {
    final i = _b58.indexOf(ch);
    if (i < 0) return null;
    n = n * base + BigInt.from(i);
  }
  var zeros = 0;
  while (zeros < s.length && s[zeros] == '1') {
    zeros++;
  }
  return concat([Uint8List(zeros), bigToBytes(n)]);
}

String base58Encode(Uint8List input) {
  var zeros = 0;
  while (zeros < input.length && input[zeros] == 0) {
    zeros++;
  }
  var n = bytesToBig(input);
  final base = BigInt.from(58);
  final chars = <String>[];
  while (n > BigInt.zero) {
    chars.add(_b58[(n % base).toInt()]);
    n = n ~/ base;
  }
  return '1' * zeros + chars.reversed.join();
}

String base58CheckEncode(Uint8List payload) =>
    base58Encode(concat([payload, dsha256(payload).sublist(0, 4)]));

/// Sagnama toplami dogruysa yuku (versiyon baytiyla birlikte) dondurur.
Uint8List? base58CheckDecode(String s) {
  final d = base58Decode(s);
  if (d == null || d.length < 5) return null;
  final payload = d.sublist(0, d.length - 4);
  final chk = d.sublist(d.length - 4);
  final want = dsha256(payload).sublist(0, 4);
  for (var i = 0; i < 4; i++) {
    if (chk[i] != want[i]) return null;
  }
  return payload;
}

const _cs = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

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

List<int>? _convertBitsStrict(List<int> data, int from, int to) {
  var acc = 0;
  var bits = 0;
  final out = <int>[];
  final maxv = (1 << to) - 1;
  for (final v in data) {
    if (v < 0 || (v >> from) != 0) return null;
    acc = ((acc << from) | v) & 0xffffffff;
    bits += from;
    while (bits >= to) {
      bits -= to;
      out.add((acc >> bits) & maxv);
    }
  }
  if (bits >= from) return null;
  if (((acc << (to - bits)) & maxv) != 0) return null;
  return out;
}

class SegwitAddr {
  final String hrp;
  final int version;
  final Uint8List program;
  const SegwitAddr(this.hrp, this.version, this.program);
}

/// Gecerli bech32 (v0) / bech32m (v1+) adresini cozer, aksi halde null.
SegwitAddr? segwitDecode(String input) {
  if (input != input.toLowerCase() && input != input.toUpperCase()) return null;
  final s = input.toLowerCase();
  final pos = s.lastIndexOf('1');
  if (pos < 1 || pos + 7 > s.length || s.length > 90) return null;
  final hrp = s.substring(0, pos);
  final data = <int>[];
  for (final ch in s.substring(pos + 1).split('')) {
    final i = _cs.indexOf(ch);
    if (i < 0) return null;
    data.add(i);
  }
  final ver = data[0];
  if (ver > 16) return null;
  final values = [
    ...hrp.codeUnits.map((c) => c >> 5),
    0,
    ...hrp.codeUnits.map((c) => c & 31),
    ...data,
  ];
  final want = ver == 0 ? 1 : 0x2bc830a3;
  if (_polymod(values) != want) return null;
  final prog = _convertBitsStrict(data.sublist(1, data.length - 6), 5, 8);
  if (prog == null || prog.length < 2 || prog.length > 40) return null;
  if (ver == 0 && prog.length != 20 && prog.length != 32) return null;
  return SegwitAddr(hrp, ver, Uint8List.fromList(prog));
}

// ---------------------------------------------------------------
// Adres dogrulama
// ---------------------------------------------------------------

String eip55(Uint8List addr20) {
  final lower = toHex(addr20);
  final hash = toHex(keccak256(lower.codeUnits));
  final sb = StringBuffer('0x');
  for (var i = 0; i < lower.length; i++) {
    final c = lower[i];
    sb.write(int.parse(hash[i], radix: 16) >= 8 ? c.toUpperCase() : c);
  }
  return sb.toString();
}

bool isValidEthAddress(String s) {
  if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(s)) return false;
  final body = s.substring(2);
  if (body == body.toLowerCase() || body == body.toUpperCase()) return true;
  return eip55(fromHex(body)) == s;
}

/// Tron adresini (T...) 21 baytlik hale (0x41 + 20 bayt) cozer.
Uint8List? tronAddressBytes(String s) {
  final p = base58CheckDecode(s);
  if (p == null || p.length != 21 || p[0] != 0x41) return null;
  return p;
}

bool isValidTronAddress(String s) => tronAddressBytes(s) != null;

/// Bitcoin adresinin kilit betigini (scriptPubKey) uretir; gecersizse null.
Uint8List? btcScriptFor(String addr) {
  final seg = segwitDecode(addr);
  if (seg != null) {
    if (seg.hrp != 'bc') return null;
    if (seg.version == 0) {
      return concat([
        [0x00, seg.program.length],
        seg.program,
      ]);
    }
    if (seg.version == 1 && seg.program.length == 32) {
      return concat([
        [0x51, 0x20],
        seg.program,
      ]);
    }
    return null;
  }
  final p = base58CheckDecode(addr);
  if (p == null || p.length != 21) return null;
  final h = p.sublist(1);
  if (p[0] == 0x00) {
    return concat([
      [0x76, 0xa9, 0x14],
      h,
      [0x88, 0xac],
    ]);
  }
  if (p[0] == 0x05) {
    return concat([
      [0xa9, 0x14],
      h,
      [0x87],
    ]);
  }
  return null;
}

String ethAddressFromPriv(Uint8List priv) => eip55(evmHashFromPriv(priv));

String tronAddressFromPriv(Uint8List priv) => base58CheckEncode(concat([
      [0x41],
      evmHashFromPriv(priv),
    ]));
