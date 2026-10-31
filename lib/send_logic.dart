import 'dart:typed_data';

import 'assets.dart';
import 'cryptox.dart';
import 'send_api.dart';
import 'state.dart';
import 'tx.dart';
import 'vault.dart';

/// Kullaniciya onay ekraninda gosterilen ve onaydan sonra gonderen islem.
class PreparedTx {
  final Asset asset;
  final String to;
  final BigInt amountRaw;
  final String feeText;
  final double feeFiatUsd; // sadece bilgi icin, bilinmiyorsa 0
  final String? warning;
  final Future<String> Function() send;
  const PreparedTx({
    required this.asset,
    required this.to,
    required this.amountRaw,
    required this.feeText,
    required this.send,
    this.feeFiatUsd = 0,
    this.warning,
  });
}

/// "0,5" veya "0.5" gibi metni en kucuk birime cevirir. Gecersizse null.
BigInt? parseAmount(String text, int decimals) {
  final t = text.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d*\.?\d*$').hasMatch(t) || t.isEmpty || t == '.') return null;
  final parts = t.split('.');
  final intPart = parts[0].isEmpty ? '0' : parts[0];
  final frac = parts.length > 1 ? parts[1] : '';
  if (frac.length > decimals) return null;
  return BigInt.parse(intPart + frac.padRight(decimals, '0'));
}

String? validateAddress(Asset a, String addr) {
  switch (a.chain) {
    case Chain.btc:
      return btcScriptFor(addr) == null ? 'Geçersiz Bitcoin adresi' : null;
    case Chain.eth:
      return isValidEthAddress(addr)
          ? null
          : 'Geçersiz Ethereum adresi (büyük/küçük harf sağlaması da kontrol edilir)';
    case Chain.trx:
      return isValidTronAddress(addr) ? null : 'Geçersiz Tron adresi';
  }
}

Future<PreparedTx> prepareSend({
  required Asset asset,
  required Wallet wallet,
  required String to,
  required String tier,
  BigInt? amount,
  bool max = false,
}) async {
  final from = app.addressOf(asset);
  if (to == from) {
    throw StateError('Kendi adresine gönderemezsin.');
  }
  switch (asset.chain) {
    case Chain.btc:
      return _prepareBtc(asset, wallet, from, to, tier, amount, max);
    case Chain.eth:
      return _prepareEth(asset, wallet, from, to, tier, amount, max);
    case Chain.trx:
      return _prepareTron(asset, wallet, from, to, amount, max);
  }
}

// ----------------------------- Bitcoin -----------------------------

Future<PreparedTx> _prepareBtc(Asset asset, Wallet wallet, String from,
    String to, String tier, BigInt? amount, bool max) async {
  final destScript = btcScriptFor(to)!;
  final utxos = await SendApi.btcUtxos(from);
  final rates = await SendApi.btcFees();
  final rate = rates[tier]!;
  final plan = planBtc(
    utxos: utxos,
    destScript: destScript,
    feeRate: rate,
    amount: max ? null : amount!.toInt(),
    sweep: max,
  );
  final ownScript = btcScriptFor(from)!;

  final outputs = <TxOut>[
    TxOut(destScript, plan.amount),
    if (plan.change > 0) TxOut(ownScript, plan.change),
  ];

  return PreparedTx(
    asset: asset,
    to: to,
    amountRaw: BigInt.from(plan.amount),
    feeText:
        '${fmtAmount(BigInt.from(plan.fee), 8)} BTC (${rate.toStringAsFixed(rate < 10 ? 1 : 0)} sat/vB)',
    warning: plan.change == 0 && !max
        ? 'Para üstü çok küçük olduğu için ağ ücretine eklendi.'
        : null,
    send: () async {
      final priv = privKeyFor(wallet.mnemonic, Chain.btc);
      // Guvenlik: anahtar, gosterilen adresle eslesmeli.
      final h = hash160(publicKeyCompressed(priv));
      final expect = concat([
        [0x00, 0x14],
        h,
      ]);
      if (toHex(expect) != toHex(ownScript)) {
        throw StateError('Anahtar adresle uyuşmuyor. İşlem iptal edildi.');
      }
      final raw = signBtc(priv: priv, inputs: plan.inputs, outputs: outputs);
      return SendApi.btcBroadcast(toHex(raw));
    },
  );
}

// ----------------------------- Ethereum -----------------------------

Future<PreparedTx> _prepareEth(Asset asset, Wallet wallet, String from,
    String to, String tier, BigInt? amount, bool max) async {
  final isToken = asset.contract != null;
  final fees = await SendApi.ethFees();
  final maxFee = fees.maxFeeFor(tier);
  final tip = fees.tipFor(tier);

  final ethBal = app.balances['eth'] ?? BigInt.zero;
  final assetBal = app.balances[asset.id] ?? BigInt.zero;

  final to20 = fromHex(to);
  late Uint8List data;
  late Uint8List target;
  late BigInt value;
  late BigInt sendAmount;

  if (isToken) {
    sendAmount = max ? assetBal : amount!;
    data = erc20TransferData(to20, sendAmount);
    target = fromHex(asset.contract!);
    value = BigInt.zero;
  } else {
    data = Uint8List(0);
    target = to20;
    value = BigInt.zero; // tahmin icin; gercek deger asagida
    sendAmount = BigInt.zero;
  }

  BigInt gas;
  try {
    gas = await SendApi.ethEstimateGas(
      from: from,
      to: isToken ? asset.contract! : to,
      value: BigInt.zero,
      data: data,
    );
  } catch (e) {
    if (isToken) {
      throw StateError('İşlem simülasyonu başarısız: $e');
    }
    gas = BigInt.from(21000);
  }
  gas = isToken
      ? (gas * BigInt.from(12)) ~/ BigInt.from(10)
      : (gas < BigInt.from(21000) ? BigInt.from(21000) : gas);
  final feeWei = gas * maxFee;

  if (isToken) {
    if (sendAmount <= BigInt.zero) throw StateError('Tutar sıfır olamaz.');
    if (sendAmount > assetBal) throw StateError('Bakiye yetersiz.');
    if (ethBal < feeWei) {
      throw StateError(
          'Ağ ücreti için ETH yetersiz. En az ${fmtAmount(feeWei, 18)} ETH gerekli.');
    }
  } else {
    if (max) {
      sendAmount = ethBal - feeWei;
      if (sendAmount <= BigInt.zero) {
        throw StateError('Bakiye ağ ücretini karşılamıyor.');
      }
    } else {
      sendAmount = amount!;
    }
    value = sendAmount;
    if (ethBal < sendAmount + feeWei) {
      throw StateError(
          'Bakiye yetersiz (tutar + en fazla ${fmtAmount(feeWei, 18)} ETH ücret).');
    }
  }

  final nonce = await SendApi.ethNonce(from);

  return PreparedTx(
    asset: asset,
    to: to,
    amountRaw: sendAmount,
    feeText: 'en fazla ${fmtAmount(feeWei, 18)} ETH',
    feeFiatUsd: toDoubleAmount(feeWei, 18),
    send: () async {
      final priv = privKeyFor(wallet.mnemonic, Chain.eth);
      final own = ethAddressFromPriv(priv);
      if (own.toLowerCase() != from.toLowerCase()) {
        throw StateError('Anahtar adresle uyuşmuyor. İşlem iptal edildi.');
      }
      final signed = signEth1559(
        priv: priv,
        chainId: 1,
        nonce: nonce,
        maxPriorityFee: tip,
        maxFee: maxFee,
        gasLimit: gas.toInt(),
        to: target,
        value: value,
        data: data,
      );
      return SendApi.ethBroadcast(signed.raw);
    },
  );
}

// ----------------------------- Tron -----------------------------

const _tronFeeLimit = 30000000; // 30 TRX
const _trxMargin = 1500000; // "tumunu gonder" icin 1.5 TRX pay

Future<PreparedTx> _prepareTron(Asset asset, Wallet wallet, String from,
    String to, BigInt? amount, bool max) async {
  final isToken = asset.contract != null;
  final trxBal = app.balances['trx'] ?? BigInt.zero;
  final assetBal = app.balances[asset.id] ?? BigInt.zero;
  final owner21 = tronAddressBytes(from)!;
  final to21 = tronAddressBytes(to)!;

  BigInt sendAmount;
  String feeText;
  String? warning;

  if (isToken) {
    sendAmount = max ? assetBal : amount!;
    if (sendAmount <= BigInt.zero) throw StateError('Tutar sıfır olamaz.');
    if (sendAmount > assetBal) throw StateError('Bakiye yetersiz.');
    if (trxBal < BigInt.from(15000000)) {
      throw StateError(
          'TRC-20 göndermek için hesapta enerji yoksa TRX yakılır. En az 15 TRX (önerilen 30 TRX) bulundurmalısın.');
    }
    feeText = 'enerji yoksa en fazla 30 TRX yanar (genelde 5-15 TRX)';
  } else {
    if (max) {
      sendAmount = trxBal - BigInt.from(_trxMargin);
      if (sendAmount <= BigInt.zero) {
        throw StateError('Bakiye ağ ücretini karşılamıyor.');
      }
      warning = 'Ücret için 1.5 TRX bakiyede bırakıldı.';
    } else {
      sendAmount = amount!;
      if (sendAmount + BigInt.from(_trxMargin) > trxBal) {
        throw StateError(
            'Bakiye yetersiz. Ağ ücreti için yaklaşık 1.5 TRX pay bırakmalısın.');
      }
    }
    feeText = 'yaklaşık 0.3-1.5 TRX (bant genişliği yoksa)';
    warning ??= 'Alıcı hesap henüz zincirde aktif değilse ek 1 TRX yanar.';
  }

  return PreparedTx(
    asset: asset,
    to: to,
    amountRaw: sendAmount,
    feeText: feeText,
    warning: warning,
    send: () async {
      final priv = privKeyFor(wallet.mnemonic, Chain.trx);
      final addr = tronAddressFromPriv(priv);
      if (addr != from) {
        throw StateError('Anahtar adresle uyuşmuyor. İşlem iptal edildi.');
      }
      final Uint8List raw;
      if (isToken) {
        raw = await SendApi.tronCreateTrc20(
          owner: from,
          token: asset.contract!,
          to: to,
          amount: sendAmount,
          feeLimitSun: _tronFeeLimit,
        );
        verifyTronTrc20(
          raw,
          owner: owner21,
          token: tronAddressBytes(asset.contract!)!,
          to: to21,
          amount: sendAmount,
          maxFeeLimitSun: _tronFeeLimit,
        );
      } else {
        raw = await SendApi.tronCreateTrx(
          owner: from,
          to: to,
          amountSun: sendAmount.toInt(),
        );
        verifyTronTrx(
          raw,
          owner: owner21,
          to: to21,
          amountSun: sendAmount.toInt(),
        );
      }
      return SendApi.tronBroadcast(signTron(priv, raw));
    },
  );
}
