import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cryptox.dart';
import 'tx.dart';

class ApiError implements Exception {
  final String message;
  ApiError(this.message);
  @override
  String toString() => message;
}

class EthFees {
  final BigInt baseFee;
  final BigInt tip;
  const EthFees(this.baseFee, this.tip);

  /// kademe: slow / normal / fast
  BigInt tipFor(String tier) {
    final floor = BigInt.from(100000000); // 0.1 gwei
    BigInt t;
    switch (tier) {
      case 'slow':
        t = tip ~/ BigInt.two;
      case 'fast':
        t = tip * BigInt.two;
      default:
        t = tip;
    }
    return t < floor ? floor : t;
  }

  BigInt maxFeeFor(String tier) => baseFee * BigInt.two + tipFor(tier);
}

class SendApi {
  static const _timeout = Duration(seconds: 20);

  // ----------------------------- Bitcoin -----------------------------

  static Future<List<BtcUtxo>> btcUtxos(String addr) async {
    final r = await http
        .get(Uri.parse('https://mempool.space/api/address/$addr/utxo'))
        .timeout(_timeout);
    if (r.statusCode != 200) throw ApiError('Bitcoin bakiyesi alınamadı.');
    final list = jsonDecode(r.body) as List<dynamic>;
    final out = <BtcUtxo>[];
    for (final e in list) {
      final m = e as Map<String, dynamic>;
      final confirmed =
          ((m['status'] as Map<String, dynamic>?)?['confirmed'] as bool?) ??
              false;
      if (!confirmed) continue;
      out.add(BtcUtxo(
        m['txid'] as String,
        m['vout'] as int,
        (m['value'] as num).toInt(),
      ));
    }
    return out;
  }

  /// sat/vB: slow, normal, fast
  static Future<Map<String, double>> btcFees() async {
    final r = await http
        .get(Uri.parse('https://mempool.space/api/v1/fees/recommended'))
        .timeout(_timeout);
    if (r.statusCode != 200) throw ApiError('Ücret bilgisi alınamadı.');
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    double n(String k) => (m[k] as num?)?.toDouble() ?? 0;
    final min = n('minimumFee') < 1 ? 1.0 : n('minimumFee');
    double fix(double v) => v < min ? min : v;
    return {
      'slow': fix(n('hourFee')),
      'normal': fix(n('halfHourFee')),
      'fast': fix(n('fastestFee')),
    };
  }

  static Future<String> btcBroadcast(String hex) async {
    final r = await http
        .post(Uri.parse('https://mempool.space/api/tx'), body: hex)
        .timeout(_timeout);
    if (r.statusCode != 200) {
      throw ApiError('İşlem ağa gönderilemedi: ${_short(r.body)}');
    }
    return r.body.trim();
  }

  // ----------------------------- Ethereum -----------------------------

  static Future<dynamic> _rpc(String method, List<dynamic> params) async {
    final r = await http
        .post(
          Uri.parse('https://ethereum-rpc.publicnode.com'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': method,
            'params': params,
          }),
        )
        .timeout(_timeout);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['error'] != null) {
      final e = j['error'];
      final msg = e is Map ? (e['message'] ?? e).toString() : e.toString();
      throw ApiError(_short(msg));
    }
    return j['result'];
  }

  static BigInt _big(dynamic h) {
    final s = (h as String).replaceFirst('0x', '');
    return s.isEmpty ? BigInt.zero : BigInt.parse(s, radix: 16);
  }

  static Future<int> ethNonce(String addr) async =>
      _big(await _rpc('eth_getTransactionCount', [addr, 'pending'])).toInt();

  static Future<EthFees> ethFees() async {
    final block = await _rpc('eth_getBlockByNumber', ['latest', false]);
    final base = _big((block as Map<String, dynamic>)['baseFeePerGas']);
    var tip = BigInt.from(1500000000);
    try {
      tip = _big(await _rpc('eth_maxPriorityFeePerGas', []));
    } catch (_) {}
    return EthFees(base, tip);
  }

  static Future<BigInt> ethEstimateGas({
    required String from,
    required String to,
    required BigInt value,
    required Uint8List data,
  }) async {
    final res = await _rpc('eth_estimateGas', [
      {
        'from': from,
        'to': to,
        'value': '0x${value.toRadixString(16)}',
        'data': '0x${toHex(data)}',
      }
    ]);
    return _big(res);
  }

  static Future<String> ethBroadcast(Uint8List raw) async {
    final res = await _rpc('eth_sendRawTransaction', ['0x${toHex(raw)}']);
    return res as String;
  }

  // ----------------------------- Tron -----------------------------

  static Future<Map<String, dynamic>> _tronPost(
    String path,
    Map<String, dynamic> body,
  ) async {
    final r = await http
        .post(
          Uri.parse('https://api.trongrid.io$path'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    if (r.statusCode != 200) {
      throw ApiError('Tron ağına ulaşılamadı (${r.statusCode}).');
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['Error'] != null) throw ApiError(_short(j['Error'].toString()));
    return j;
  }

  static Future<Uint8List> tronCreateTrx({
    required String owner,
    required String to,
    required int amountSun,
  }) async {
    final j = await _tronPost('/wallet/createtransaction', {
      'owner_address': owner,
      'to_address': to,
      'amount': amountSun,
      'visible': true,
    });
    final hex = j['raw_data_hex'] as String?;
    if (hex == null) throw ApiError('Tron işlemi hazırlanamadı.');
    return fromHex(hex);
  }

  static Future<Uint8List> tronCreateTrc20({
    required String owner,
    required String token,
    required String to,
    required BigInt amount,
    required int feeLimitSun,
  }) async {
    final to21 = tronAddressBytes(to)!;
    final param = toHex(concat([Uint8List(12), to21.sublist(1)])) +
        toHex(bigToBytes(amount, 32));
    final j = await _tronPost('/wallet/triggersmartcontract', {
      'owner_address': owner,
      'contract_address': token,
      'function_selector': 'transfer(address,uint256)',
      'parameter': param,
      'fee_limit': feeLimitSun,
      'call_value': 0,
      'visible': true,
    });
    final tx = j['transaction'] as Map<String, dynamic>?;
    final hex = tx?['raw_data_hex'] as String?;
    if (hex == null) throw ApiError('TRC-20 işlemi hazırlanamadı.');
    return fromHex(hex);
  }

  static Future<String> tronBroadcast(TronSigned s) async {
    final j = await _tronPost('/wallet/broadcasthex', {
      'transaction': toHex(s.broadcastHex),
    });
    if (j['result'] != true) {
      var msg = (j['message'] ?? j['code'] ?? 'bilinmeyen hata').toString();
      // Tron hata mesajini hex olarak dondurur.
      if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(msg) && msg.length.isEven) {
        try {
          msg = utf8.decode(fromHex(msg));
        } catch (_) {}
      }
      throw ApiError('İşlem reddedildi: ${_short(msg)}');
    }
    return s.txId;
  }

  static String _short(String s) =>
      s.length > 160 ? '${s.substring(0, 160)}…' : s;
}
