// Bu degerler Dart'tan bagimsiz, BIP-143 / EIP-155 resmi orneklerine karsi
// dogrulanmis bir referans uygulamayla uretildi. Bir tanesi bile tutmazsa APK
// uretilmez.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orvexa/assets.dart';
import 'package:orvexa/chains.dart';
import 'package:orvexa/cryptox.dart';
import 'package:orvexa/tx.dart';

const mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

void main() {
  group('adres turetme', () {
    test('BTC / ETH / TRX', () {
      final a = addressesFor(mnemonic);
      expect(a.btc, 'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu');
      expect(a.eth, '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
      expect(a.trx, 'TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH');
    });
    test('ETH bilinen adres (abandon... about)', () {
      expect(a0().eth.toLowerCase(), '0x9858effd232b4033e47d90003d41ec34ecaeda94');
    });
    test('anahtardan adres', () {
      final k = privKeyFor(mnemonic, Chain.eth);
      expect(ethAddressFromPriv(k), '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
      final t = privKeyFor(mnemonic, Chain.trx);
      expect(tronAddressFromPriv(t), 'TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH');
    });
  });

  group('ethereum imza', () {
    final priv = fromHex('1ab42cc412b618bdea3a599e3c9bae199ebf030895b039e9db1e30dafb12b727');
    final to = fromHex('d8da6bf26964af9d7eed9e03e53415d37aa96045');

    test('keccak256 bos girdi', () {
      expect(toHex(keccak256([])),
          'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470');
    });

    test('ETH transferi (EIP-1559)', () {
      final s = signEth1559(
        priv: priv,
        chainId: 1,
        nonce: 7,
        maxPriorityFee: BigInt.from(1500000000),
        maxFee: BigInt.from(30000000000),
        gasLimit: 21000,
        to: to,
        value: BigInt.from(10).pow(17),
        data: Uint8List(0),
      );
      expect(toHex(s.raw), '02f87301078459682f008506fc23ac0082520894d8da6bf26964af9d7eed9e03e53415d37aa9604588016345785d8a000080c001a034f5565c337fe4783fc47e926b6b6aba73c06c3686b55af4da514e67e673bec6a060ec6906c5f2254f6e92d17cf82db2aa25617393f372bbea6029feddb86bae92');
    });

    test('USDT transferi', () {
      final data = erc20TransferData(to, BigInt.from(1500000));
      expect(toHex(data), 'a9059cbb000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045000000000000000000000000000000000000000000000000000000000016e360');
      final s = signEth1559(
        priv: priv,
        chainId: 1,
        nonce: 8,
        maxPriorityFee: BigInt.from(1000000000),
        maxFee: BigInt.from(25000000000),
        gasLimit: 65000,
        to: fromHex('dac17f958d2ee523a2206206994597c13d831ec7'),
        value: BigInt.zero,
        data: data,
      );
      expect(toHex(s.raw), '02f8b00108843b9aca008505d21dba0082fde894dac17f958d2ee523a2206206994597c13d831ec780b844a9059cbb000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045000000000000000000000000000000000000000000000000000000000016e360c001a063b9625578beda8ddb5a1e16666e3a9e0e9c1fc0e858e2d4fa9da99f3a8f9a60a048f19a9f3d8c70e40431a79217eb4a11bf30e998936656103671c6668fa1c589');
    });
  });

  group('bitcoin imza', () {
    final priv = privKeyFor(mnemonic, Chain.btc);
    final inputs = [
    BtcUtxo('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 1, 100000),
    BtcUtxo('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbcc', 0, 50000)
    ];
    final dest = btcScriptFor('bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g')!;
    final own = btcScriptFor('bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu')!;

    test('P2WPKH, 2 girdi, para ustu', () {
      final raw = signBtc(
        priv: priv,
        inputs: inputs,
        outputs: [TxOut(dest, 40000), TxOut(own, 108000)],
      );
      expect(toHex(raw), '02000000000102aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0100000000fdffffffccbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb0000000000fdffffff02409c0000000000001600149c90f934ea51fa0f6504177043e0908da6929983e0a5010000000000160014c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e202483045022100919bfc42bb549ba1ee4550c78aae46f2845249253f720b86038295a7daefe190022052d7b3a0e567ef4547bc05983cb486d8b24e89e6512b88a9345e490b956ac1bc01210330d54fd0dd420a6e5f8d3624f5f3482cae350f79d5f0753bf5beef9c2d91af3c0247304402202229687703b8c0460a02809ee9b8b12cd4e14cebc412aedd301b82167fea153a0220415f95df5cffa0ff70c54e39651cd1138f67e787f6bce69b75b02504e2d053be01210330d54fd0dd420a6e5f8d3624f5f3482cae350f79d5f0753bf5beef9c2d91af3c00000000');
    });

    test('ucret ve para ustu hesabi', () {
      final plan = planBtc(
        utxos: inputs,
        destScript: dest,
        feeRate: 10,
        amount: 40000,
      );
      expect(plan.inputs.length, 1);
      expect(plan.amount + plan.fee + plan.change, 100000);
      expect(plan.fee, (10 * (11 + 68 + 31 + 31)).ceil());
    });

    test('yetersiz bakiye', () {
      expect(
        () => planBtc(utxos: inputs, destScript: dest, feeRate: 10, amount: 200000),
        throwsA(isA<StateError>()),
      );
    });

    test('tum bakiyeyi gonder', () {
      final plan = planBtc(
        utxos: inputs,
        destScript: dest,
        feeRate: 10,
        sweep: true,
      );
      expect(plan.change, 0);
      expect(plan.amount + plan.fee, 150000);
    });
  });

  group('adres dogrulama', () {
    test('bitcoin turleri', () {
      expect(btcScriptFor('bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu'), isNotNull);
      expect(toHex(btcScriptFor('16dytAU1ap72NmknXYnBg6jAx992Hw4M7v')!), '76a9143dd7161afd7b95814e96863f1076c7c015c3e92a88ac');
      expect(toHex(btcScriptFor('37KzohxT8iRQTwTDeeSn6j676fRjsPHsvL')!), 'a9143dd7161afd7b95814e96863f1076c7c015c3e92a87');
      expect(toHex(btcScriptFor('bc1py9ymt6adxzgr20ha4a3smcrn67xkjkuacxdy33sgqpu3gnscucgs8s063c')!), '51202149b5ebad3090353efdaf630de073d78d695b9dc19a48c6080079144e18e611');
    });
    test('bozuk bitcoin adresleri reddedilir', () {
      expect(btcScriptFor('bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyq'), isNull);
      expect(btcScriptFor('bc1'), isNull);
      expect(btcScriptFor('1BoatSLRHtKNngkdXEeobR76b53LETtpyX'), isNull);
      expect(btcScriptFor('0x9858EfFD232B4033E47d90003D41EC34EcaEda94'), isNull);
    });
    test('ethereum', () {
      expect(isValidEthAddress('0x9858EfFD232B4033E47d90003D41EC34EcaEda94'), isTrue);
      expect(isValidEthAddress('0x9858effd232b4033e47d90003d41ec34ecaeda94'), isTrue);
      // tek harf buyuklugu bozuk: sagama basarisiz
      expect(isValidEthAddress('0x9858efFD232B4033E47d90003D41EC34EcaEda94'), isFalse);
      expect(isValidEthAddress('0x1234'), isFalse);
    });
    test('tron', () {
      expect(isValidTronAddress('TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH'), isTrue);
      expect(isValidTronAddress('TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t'), isTrue);
      expect(isValidTronAddress('TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdG'), isFalse);
      expect(isValidTronAddress('bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu'), isFalse);
    });
  });

  group('tron', () {
    final owner = tronAddressBytes('TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH')!;
    final to = tronAddressBytes('TSeJkUh4Qv67VNFwY8LaAxERygNdy6NQZK')!;
    final token = tronAddressBytes('TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t')!;
    final raw1 = fromHex('0a021234220801010101010101014080e6b1cba3335a67080112630a2d747970652e676f6f676c65617069732e636f6d2f70726f746f636f6c2e5472616e73666572436f6e747261637412320a1541c8599111f29c1e1e061265b4af93ea1f274ad78a121541b6e708a39781c96bd399c7657780ff9fe9f052a81887ad4b70a091aecba333');
    final raw2 = fromHex('0a021234220801010101010101014080e6b1cba3335aae01081f12a9010a31747970652e676f6f676c65617069732e636f6d2f70726f746f636f6c2e54726967676572536d617274436f6e747261637412740a1541c8599111f29c1e1e061265b4af93ea1f274ad78a121541a614f803b6fd780986a42c78ec9c7f77e6ded13c2244a9059cbb000000000000000000000000b6e708a39781c96bd399c7657780ff9fe9f052a800000000000000000000000000000000000000000000000000000000002625a070a091aecba33390018087a70e');

    test('TRX transferi dogrulanir', () {
      verifyTronTrx(raw1, owner: owner, to: to, amountSun: 1234567);
    });
    test('yanlis tutar / alici reddedilir', () {
      expect(() => verifyTronTrx(raw1, owner: owner, to: to, amountSun: 1234568),
          throwsA(isA<StateError>()));
      expect(() => verifyTronTrx(raw1, owner: owner, to: owner, amountSun: 1234567),
          throwsA(isA<StateError>()));
    });
    test('TRC-20 dogrulanir', () {
      verifyTronTrc20(raw2,
          owner: owner,
          token: token,
          to: to,
          amount: BigInt.from(2500000),
          maxFeeLimitSun: 30000000);
    });
    test('TRC-20 yanlis tutar / yuksek ucret limiti reddedilir', () {
      expect(
          () => verifyTronTrc20(raw2,
              owner: owner,
              token: token,
              to: to,
              amount: BigInt.from(2500001),
              maxFeeLimitSun: 30000000),
          throwsA(isA<StateError>()));
      expect(
          () => verifyTronTrc20(raw2,
              owner: owner,
              token: token,
              to: to,
              amount: BigInt.from(2500000),
              maxFeeLimitSun: 1000000),
          throwsA(isA<StateError>()));
    });
    test('imza ve yayin verisi', () {
      final priv = privKeyFor(mnemonic, Chain.trx);
      final s = signTron(priv, raw1);
      expect(s.txId, '648f06baaf607b204e8b7d85967efc920ef98e90a8de9b5dcc202d382bcbcd0d');
      expect(toHex(s.broadcastHex), '0a85010a021234220801010101010101014080e6b1cba3335a67080112630a2d747970652e676f6f676c65617069732e636f6d2f70726f746f636f6c2e5472616e73666572436f6e747261637412320a1541c8599111f29c1e1e061265b4af93ea1f274ad78a121541b6e708a39781c96bd399c7657780ff9fe9f052a81887ad4b70a091aecba3331241b1c497abc24dfb1d9756f25b41adf8261b5040c6cf09ac9484d67a581cfce564572c97f6e19338dc548e1a345094435631a81335234a9a4e6fc9a87f13f9df7a00');
    });
  });
}

AddressesHolder a0() => AddressesHolder(addressesFor(mnemonic).eth);

class AddressesHolder {
  final String eth;
  AddressesHolder(this.eth);
}
