import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;

import 'assets.dart';
import 'cryptox.dart';

// ---------------------------------------------------------------
// Anahtar turetme (sadece gonderme aninda, bellekte kisa sure)
// ---------------------------------------------------------------

Uint8List privKeyFor(String mnemonic, Chain chain) {
  final root = bip32.BIP32.fromSeed(bip39.mnemonicToSeed(mnemonic));
  final path = switch (chain) {
    Chain.btc => "m/84'/0'/0'/0/0",
    Chain.eth => "m/44'/60'/0'/0/0",
    Chain.trx => "m/44'/195'/0'/0/0",
  };
  return root.derivePath(path).privateKey!;
}

// ---------------------------------------------------------------
// Bitcoin (P2WPKH, BIP-143)
// ---------------------------------------------------------------

const int btcDust = 546;

class BtcUtxo {
  final String txid; // blok gezgininde gorunen (ters) sira
  final int vout;
  final int value;
  const BtcUtxo(this.txid, this.vout, this.value);
}

class TxOut {
  final Uint8List script;
  final int value;
  const TxOut(this.script, this.value);
}

class BtcPlan {
  final List<BtcUtxo> inputs;
  final int amount;
  final int fee;
  final int change;
  const BtcPlan(this.inputs, this.amount, this.fee, this.change);
}

int _btcVsize(int nIn, int destScriptLen, bool hasChange) =>
    11 + 68 * nIn + (9 + destScriptLen) + (hasChange ? 31 : 0);

/// Para birimi secimi ve ucret hesabi. [sweep] true ise tum bakiye gonderilir.
BtcPlan planBtc({
  required List<BtcUtxo> utxos,
  required Uint8List destScript,
  required double feeRate,
  int? amount,
  bool sweep = false,
}) {
  if (utxos.isEmpty) {
    throw StateError('Harcanabilir (onaylı) bakiye yok.');
  }
  final sorted = [...utxos]..sort((a, b) => b.value.compareTo(a.value));

  if (sweep) {
    final total = sorted.fold<int>(0, (s, u) => s + u.value);
    final fee = (feeRate * _btcVsize(sorted.length, destScript.length, false))
        .ceil();
    final send = total - fee;
    if (send < btcDust) {
      throw StateError('Bakiye ağ ücretini karşılamıyor.');
    }
    return BtcPlan(sorted, send, fee, 0);
  }

  final amt = amount!;
  if (amt < btcDust) {
    throw StateError('Tutar çok küçük (en az $btcDust satoshi).');
  }
  final chosen = <BtcUtxo>[];
  var total = 0;
  for (final u in sorted) {
    chosen.add(u);
    total += u.value;
    final feeWithChange =
        (feeRate * _btcVsize(chosen.length, destScript.length, true)).ceil();
    if (total >= amt + feeWithChange) {
      final change = total - amt - feeWithChange;
      if (change >= btcDust) {
        return BtcPlan(chosen, amt, feeWithChange, change);
      }
      // Para ustu cok kucuk: ucrete eklenir.
      return BtcPlan(chosen, amt, total - amt, 0);
    }
    final feeNoChange =
        (feeRate * _btcVsize(chosen.length, destScript.length, false)).ceil();
    if (total >= amt + feeNoChange && total < amt + feeWithChange) {
      return BtcPlan(chosen, amt, total - amt, 0);
    }
  }
  throw StateError('Bakiye yetersiz (tutar + ağ ücreti).');
}

Uint8List _le32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
Uint8List _le64(int v) =>
    Uint8List(8)..buffer.asByteData().setUint64(0, v, Endian.little);

Uint8List _varint(int n) {
  if (n < 0xfd) return Uint8List.fromList([n]);
  if (n <= 0xffff) {
    return Uint8List.fromList([0xfd, n & 0xff, (n >> 8) & 0xff]);
  }
  throw ArgumentError('varint cok buyuk');
}

Uint8List _outpoint(BtcUtxo u) => concat([
      Uint8List.fromList(fromHex(u.txid).reversed.toList()),
      _le32(u.vout),
    ]);

/// Tum girdileri tek bir P2WPKH anahtariyla imzalar, ham islem baytlarini doner.
Uint8List signBtc({
  required Uint8List priv,
  required List<BtcUtxo> inputs,
  required List<TxOut> outputs,
}) {
  final pub = publicKeyCompressed(priv);
  final h160 = hash160(pub);
  final scriptCode = concat([
    [0x19, 0x76, 0xa9, 0x14],
    h160,
    [0x88, 0xac],
  ]);
  final version = _le32(2);
  final seq = _le32(0xfffffffd);
  final locktime = _le32(0);

  final hashPrevouts = dsha256(concat(inputs.map(_outpoint)));
  final hashSequence = dsha256(concat(inputs.map((_) => seq)));
  final outBytes = concat(outputs.map((o) => concat([
        _le64(o.value),
        _varint(o.script.length),
        o.script,
      ])));
  final hashOutputs = dsha256(outBytes);

  final witnesses = <Uint8List>[];
  for (final u in inputs) {
    final pre = concat([
      version,
      hashPrevouts,
      hashSequence,
      _outpoint(u),
      scriptCode,
      _le64(u.value),
      seq,
      hashOutputs,
      locktime,
      _le32(1), // SIGHASH_ALL
    ]);
    final sh = dsha256(pre);
    final sig = ecdsaSign(priv, sh);
    final der = concat([derSig(sig.r, sig.s), [0x01]]);
    witnesses.add(concat([
      [0x02],
      _varint(der.length),
      der,
      _varint(pub.length),
      pub,
    ]));
  }

  return concat([
    version,
    [0x00, 0x01],
    _varint(inputs.length),
    ...inputs.map((u) => concat([_outpoint(u), [0x00], seq])),
    _varint(outputs.length),
    outBytes,
    ...witnesses,
    locktime,
  ]);
}

// ---------------------------------------------------------------
// Ethereum (EIP-1559, tip 2)
// ---------------------------------------------------------------

class EthSigned {
  final Uint8List raw;
  final String txHash;
  const EthSigned(this.raw, this.txHash);
}

EthSigned signEth1559({
  required Uint8List priv,
  required int chainId,
  required int nonce,
  required BigInt maxPriorityFee,
  required BigInt maxFee,
  required int gasLimit,
  required Uint8List to,
  required BigInt value,
  required Uint8List data,
}) {
  final fields = [
    chainId,
    nonce,
    maxPriorityFee,
    maxFee,
    gasLimit,
    to,
    value,
    data,
    <dynamic>[],
  ];
  final sigHash = keccak256(concat([
    [0x02],
    rlp(fields),
  ]));
  final sig = ecdsaSign(priv, sigHash);
  final raw = concat([
    [0x02],
    rlp([...fields, sig.rec, sig.r, sig.s]),
  ]);
  return EthSigned(raw, '0x${toHex(keccak256(raw))}');
}

/// ERC-20 transfer(address,uint256) cagri verisi.
Uint8List erc20TransferData(Uint8List to20, BigInt amount) => concat([
      [0xa9, 0x05, 0x9c, 0xbb],
      Uint8List(12),
      to20,
      bigToBytes(amount, 32),
    ]);

// ---------------------------------------------------------------
// Tron
// ---------------------------------------------------------------

class _Pb {
  final Uint8List b;
  int i = 0;
  _Pb(this.b);

  bool get done => i >= b.length;

  int varint() {
    var r = 0;
    var shift = 0;
    while (true) {
      if (i >= b.length) throw const FormatException('protobuf: erken bitti');
      final x = b[i++];
      r |= (x & 0x7f) << shift;
      if ((x & 0x80) == 0) break;
      shift += 7;
      if (shift > 63) throw const FormatException('protobuf: varint');
    }
    return r;
  }

  Uint8List bytes() {
    final n = varint();
    if (n < 0 || i + n > b.length) {
      throw const FormatException('protobuf: uzunluk');
    }
    final out = Uint8List.sublistView(b, i, i + n);
    i += n;
    return out;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        i += 8;
      case 2:
        bytes();
      case 5:
        i += 4;
      default:
        throw const FormatException('protobuf: bilinmeyen tur');
    }
  }
}

class TronContract {
  int type = 0; // 1 = TransferContract, 31 = TriggerSmartContract
  Uint8List? owner;
  Uint8List? to;
  int amount = 0;
  Uint8List? contract;
  int callValue = 0;
  Uint8List? data;
  int feeLimit = 0;
}

/// Sunucunun dondurdugu ham islemi (raw_data) cozer.
TronContract parseTronRaw(Uint8List raw) {
  final p = _Pb(raw);
  final contracts = <Uint8List>[];
  var feeLimit = 0;
  while (!p.done) {
    final tag = p.varint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 11 && wire == 2) {
      contracts.add(p.bytes());
    } else if (field == 18 && wire == 0) {
      feeLimit = p.varint();
    } else {
      p.skip(wire);
    }
  }
  if (contracts.length != 1) {
    throw StateError('Beklenmeyen islem yapisi (sozlesme sayisi).');
  }
  final res = TronContract()..feeLimit = feeLimit;

  Uint8List? paramValue;
  final c = _Pb(contracts.first);
  while (!c.done) {
    final tag = c.varint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 0) {
      res.type = c.varint();
    } else if (field == 2 && wire == 2) {
      final any = _Pb(c.bytes());
      while (!any.done) {
        final t = any.varint();
        if ((t >> 3) == 2 && (t & 7) == 2) {
          paramValue = any.bytes();
        } else {
          any.skip(t & 7);
        }
      }
    } else {
      c.skip(wire);
    }
  }
  if (paramValue == null) throw StateError('Islem parametresi yok.');

  final v = _Pb(paramValue);
  while (!v.done) {
    final tag = v.varint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (res.type == 1) {
      if (field == 1 && wire == 2) {
        res.owner = v.bytes();
      } else if (field == 2 && wire == 2) {
        res.to = v.bytes();
      } else if (field == 3 && wire == 0) {
        res.amount = v.varint();
      } else {
        v.skip(wire);
      }
    } else if (res.type == 31) {
      if (field == 1 && wire == 2) {
        res.owner = v.bytes();
      } else if (field == 2 && wire == 2) {
        res.contract = v.bytes();
      } else if (field == 3 && wire == 0) {
        res.callValue = v.varint();
      } else if (field == 4 && wire == 2) {
        res.data = v.bytes();
      } else {
        v.skip(wire);
      }
    } else {
      v.skip(wire);
    }
  }
  return res;
}

bool _eq(Uint8List? a, Uint8List b) {
  if (a == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Sunucunun hazirladigi TRX transferinin bizim istedigimizle ayni oldugunu dogrular.
void verifyTronTrx(
  Uint8List raw, {
  required Uint8List owner,
  required Uint8List to,
  required int amountSun,
}) {
  final t = parseTronRaw(raw);
  if (t.type != 1 ||
      !_eq(t.owner, owner) ||
      !_eq(t.to, to) ||
      t.amount != amountSun) {
    throw StateError('Sunucudan gelen islem istenenle uyusmuyor. Iptal edildi.');
  }
}

/// TRC-20 transferini dogrular.
void verifyTronTrc20(
  Uint8List raw, {
  required Uint8List owner,
  required Uint8List token,
  required Uint8List to,
  required BigInt amount,
  required int maxFeeLimitSun,
}) {
  final t = parseTronRaw(raw);
  final want = erc20TransferData(to.sublist(1), amount);
  if (t.type != 31 ||
      !_eq(t.owner, owner) ||
      !_eq(t.contract, token) ||
      t.callValue != 0 ||
      !_eq(t.data, want) ||
      t.feeLimit > maxFeeLimitSun) {
    throw StateError('Sunucudan gelen islem istenenle uyusmuyor. Iptal edildi.');
  }
}

class TronSigned {
  final String txId;
  final Uint8List broadcastHex; // Transaction mesaji (raw_data + imza)
  const TronSigned(this.txId, this.broadcastHex);
}

TronSigned signTron(Uint8List priv, Uint8List raw) {
  final id = sha256(raw);
  final sig = ecdsaSign(priv, id);
  final sigBytes = concat([
    bigToBytes(sig.r, 32),
    bigToBytes(sig.s, 32),
    [sig.rec],
  ]);
  final tx = concat([
    [0x0a],
    _pbLen(raw.length),
    raw,
    [0x12, sigBytes.length],
    sigBytes,
  ]);
  return TronSigned(toHex(id), tx);
}

Uint8List _pbLen(int n) {
  final out = <int>[];
  var v = n;
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return Uint8List.fromList(out);
}
