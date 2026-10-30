import 'dart:convert';

import 'package:http/http.dart' as http;

import 'assets.dart';
import 'chains.dart';

class Price {
  final double usd;
  final double usdChange;
  final double tryy;
  final double tryChange;
  const Price(this.usd, this.usdChange, this.tryy, this.tryChange);

  double value(String cur) => cur == 'try' ? tryy : usd;
  double change(String cur) => cur == 'try' ? tryChange : usdChange;
}

/// Acik genel API'ler: mempool.space (BTC), publicnode (ETH RPC),
/// TronGrid (TRX) ve CoinGecko (fiyat). Hicbiri anahtar/sirri gondermez;
/// sadece genel adresler sorgulanir.
class Api {
  static const _timeout = Duration(seconds: 15);

  static Future<Map<String, BigInt>> balances(ChainAddresses a) async {
    final out = <String, BigInt>{};
    await Future.wait([
      _btc(a.btc, out),
      _eth(a.eth, out),
      _trx(a.trx, out),
    ]);
    return out;
  }

  static Future<void> _btc(String addr, Map<String, BigInt> out) async {
    try {
      final r = await http
          .get(Uri.parse('https://mempool.space/api/address/$addr'))
          .timeout(_timeout);
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      int net(Map<String, dynamic> m) =>
          (m['funded_txo_sum'] as int) - (m['spent_txo_sum'] as int);
      final total = net(j['chain_stats'] as Map<String, dynamic>) +
          net(j['mempool_stats'] as Map<String, dynamic>);
      out['btc'] = BigInt.from(total < 0 ? 0 : total);
    } catch (_) {}
  }

  static Future<dynamic> _ethRpc(String method, List<dynamic> params) async {
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
    return j['result'];
  }

  static BigInt _hexToBig(String h) {
    final s = h.startsWith('0x') ? h.substring(2) : h;
    return s.isEmpty ? BigInt.zero : BigInt.parse(s, radix: 16);
  }

  static Future<void> _eth(String addr, Map<String, BigInt> out) async {
    try {
      final bal = await _ethRpc('eth_getBalance', [addr, 'latest']);
      if (bal is String) out['eth'] = _hexToBig(bal);
    } catch (_) {}
    try {
      final padded = addr.substring(2).toLowerCase().padLeft(64, '0');
      final res = await _ethRpc('eth_call', [
        {'to': usdtEthContract, 'data': '0x70a08231$padded'},
        'latest',
      ]);
      if (res is String) out['usdt_eth'] = _hexToBig(res);
    } catch (_) {}
  }

  static Future<void> _trx(String addr, Map<String, BigInt> out) async {
    try {
      final r = await http
          .get(Uri.parse('https://api.trongrid.io/v1/accounts/$addr'))
          .timeout(_timeout);
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final data = (j['data'] as List<dynamic>?) ?? [];
      if (data.isEmpty) {
        // Hesap zincirde henuz aktif degil: bakiye 0.
        out['trx'] = BigInt.zero;
        out['usdt_trx'] = BigInt.zero;
        return;
      }
      final acc = data.first as Map<String, dynamic>;
      out['trx'] = BigInt.from((acc['balance'] as num?) ?? 0);
      var usdt = BigInt.zero;
      final tokens = (acc['trc20'] as List<dynamic>?) ?? [];
      for (final t in tokens) {
        final m = t as Map<String, dynamic>;
        final v = m[usdtTrxContract];
        if (v != null) usdt = BigInt.parse(v.toString());
      }
      out['usdt_trx'] = usdt;
    } catch (_) {}
  }

  static Future<Map<String, Price>> prices() async {
    try {
      final ids = allAssets.map((a) => a.cgId).toSet().join(',');
      final r = await http
          .get(Uri.parse(
            'https://api.coingecko.com/api/v3/simple/price'
            '?ids=$ids&vs_currencies=usd,try&include_24hr_change=true',
          ))
          .timeout(_timeout);
      if (r.statusCode != 200) return {};
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      double n(dynamic v) => (v as num?)?.toDouble() ?? 0;
      return {
        for (final e in j.entries)
          e.key: Price(
            n((e.value as Map<String, dynamic>)['usd']),
            n((e.value as Map<String, dynamic>)['usd_24h_change']),
            n((e.value as Map<String, dynamic>)['try']),
            n((e.value as Map<String, dynamic>)['try_24h_change']),
          ),
      };
    } catch (_) {
      return {};
    }
  }
}
