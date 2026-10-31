import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'assets.dart';
import 'cryptox.dart';
import 'screens.dart';
import 'state.dart';
import 'theme.dart';

class TxItem {
  final String hash;
  final DateTime? time;
  final bool incoming;
  final BigInt amount;
  final String counterparty;
  final bool pending;
  final bool failed;
  const TxItem({
    required this.hash,
    required this.time,
    required this.incoming,
    required this.amount,
    required this.counterparty,
    this.pending = false,
    this.failed = false,
  });
}

dynamic _at(dynamic m, List<String> path) {
  var cur = m;
  for (final k in path) {
    if (cur is Map) {
      cur = cur[k];
    } else {
      return null;
    }
  }
  return cur;
}

Future<dynamic> _getJson(String url) async {
  final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  return jsonDecode(r.body);
}

Future<List<TxItem>> fetchHistory(Asset a, String addr) async {
  switch (a.chain) {
    case Chain.btc:
      return _btc(addr);
    case Chain.eth:
      return a.contract == null ? _ethNative(addr) : _ethToken(a, addr);
    case Chain.trx:
      return a.contract == null ? _trxNative(addr) : _trxToken(a, addr);
  }
}

Future<List<TxItem>> _btc(String addr) async {
  final list = await _getJson('https://mempool.space/api/address/$addr/txs')
      as List<dynamic>;
  final out = <TxItem>[];
  for (final e in list) {
    var inOurs = 0;
    var outOurs = 0;
    String? firstIn;
    String? firstOut;
    for (final vin in (_at(e, ['vin']) as List<dynamic>? ?? [])) {
      final pa = _at(vin, ['prevout', 'scriptpubkey_address']) as String?;
      final v = (_at(vin, ['prevout', 'value']) as num?)?.toInt() ?? 0;
      if (pa == addr) {
        inOurs += v;
      } else {
        firstIn ??= pa;
      }
    }
    for (final vo in (_at(e, ['vout']) as List<dynamic>? ?? [])) {
      final pa = _at(vo, ['scriptpubkey_address']) as String?;
      final v = (_at(vo, ['value']) as num?)?.toInt() ?? 0;
      if (pa == addr) {
        outOurs += v;
      } else {
        firstOut ??= pa;
      }
    }
    final net = outOurs - inOurs;
    if (net == 0) continue;
    final confirmed = _at(e, ['status', 'confirmed']) == true;
    final bt = (_at(e, ['status', 'block_time']) as num?)?.toInt();
    out.add(TxItem(
      hash: e['txid'] as String,
      time: bt == null ? null : DateTime.fromMillisecondsSinceEpoch(bt * 1000),
      incoming: net > 0,
      amount: BigInt.from(net.abs()),
      counterparty: (net > 0 ? firstIn : firstOut) ?? '—',
      pending: !confirmed,
    ));
  }
  return out;
}

DateTime? _iso(dynamic s) => s is String ? DateTime.tryParse(s)?.toLocal() : null;

Future<List<TxItem>> _ethNative(String addr) async {
  final j = await _getJson(
      'https://eth.blockscout.com/api/v2/addresses/$addr/transactions');
  final items = (_at(j, ['items']) as List<dynamic>?) ?? [];
  final out = <TxItem>[];
  for (final e in items) {
    final value = BigInt.tryParse('${_at(e, ['value'])}') ?? BigInt.zero;
    if (value == BigInt.zero) continue;
    final from = '${_at(e, ['from', 'hash'])}';
    final to = '${_at(e, ['to', 'hash'])}';
    final incoming = to.toLowerCase() == addr.toLowerCase();
    final status = '${_at(e, ['status'])}';
    out.add(TxItem(
      hash: '${_at(e, ['hash'])}',
      time: _iso(_at(e, ['timestamp'])),
      incoming: incoming,
      amount: value,
      counterparty: incoming ? from : to,
      pending: status == 'null' || status == 'pending',
      failed: status == 'error',
    ));
  }
  return out;
}

Future<List<TxItem>> _ethToken(Asset a, String addr) async {
  final j = await _getJson(
      'https://eth.blockscout.com/api/v2/addresses/$addr/token-transfers?type=ERC-20');
  final items = (_at(j, ['items']) as List<dynamic>?) ?? [];
  final out = <TxItem>[];
  for (final e in items) {
    final token = ('${_at(e, ['token', 'address_hash'])}'
            '${_at(e, ['token', 'address'])}')
        .toLowerCase();
    if (!token.contains(a.contract!.toLowerCase())) continue;
    final from = '${_at(e, ['from', 'hash'])}';
    final to = '${_at(e, ['to', 'hash'])}';
    final incoming = to.toLowerCase() == addr.toLowerCase();
    out.add(TxItem(
      hash: '${_at(e, ['transaction_hash']) ?? _at(e, ['tx_hash']) ?? ''}',
      time: _iso(_at(e, ['timestamp'])),
      incoming: incoming,
      amount: BigInt.tryParse('${_at(e, ['total', 'value'])}') ?? BigInt.zero,
      counterparty: incoming ? from : to,
    ));
  }
  return out;
}

String _tronHexToBase58(String hex) =>
    base58CheckEncode(fromHex(hex));

Future<List<TxItem>> _trxNative(String addr) async {
  final j = await _getJson(
      'https://api.trongrid.io/v1/accounts/$addr/transactions?limit=40');
  final items = (_at(j, ['data']) as List<dynamic>?) ?? [];
  final out = <TxItem>[];
  for (final e in items) {
    final c = (_at(e, ['raw_data', 'contract']) as List<dynamic>?) ?? [];
    if (c.isEmpty || _at(c.first, ['type']) != 'TransferContract') continue;
    final v = _at(c.first, ['parameter', 'value']);
    final owner = _tronHexToBase58('${_at(v, ['owner_address'])}');
    final to = _tronHexToBase58('${_at(v, ['to_address'])}');
    final ts = (_at(e, ['block_timestamp']) as num?)?.toInt();
    final ret = _at(e, ['ret']);
    final status = ret is List && ret.isNotEmpty ? '${_at(ret.first, ['contractRet'])}' : '';
    final incoming = to == addr;
    out.add(TxItem(
      hash: '${_at(e, ['txID'])}',
      time: ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts),
      incoming: incoming,
      amount: BigInt.from((_at(v, ['amount']) as num?) ?? 0),
      counterparty: incoming ? owner : to,
      failed: status.isNotEmpty && status != 'SUCCESS',
    ));
  }
  return out;
}

Future<List<TxItem>> _trxToken(Asset a, String addr) async {
  final j = await _getJson(
      'https://api.trongrid.io/v1/accounts/$addr/transactions/trc20'
      '?limit=40&contract_address=${a.contract}');
  final items = (_at(j, ['data']) as List<dynamic>?) ?? [];
  final out = <TxItem>[];
  for (final e in items) {
    final from = '${_at(e, ['from'])}';
    final to = '${_at(e, ['to'])}';
    final ts = (_at(e, ['block_timestamp']) as num?)?.toInt();
    final incoming = to == addr;
    out.add(TxItem(
      hash: '${_at(e, ['transaction_id'])}',
      time: ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts),
      incoming: incoming,
      amount: BigInt.tryParse('${_at(e, ['value'])}') ?? BigInt.zero,
      counterparty: incoming ? from : to,
    ));
  }
  return out;
}

String _fmtTime(DateTime? t) {
  if (t == null) return 'Beklemede';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
}

String shortAddr(String s) =>
    s.length <= 16 ? s : '${s.substring(0, 8)}…${s.substring(s.length - 6)}';

class HistoryList extends StatefulWidget {
  final Asset asset;
  const HistoryList({super.key, required this.asset});

  @override
  State<HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<HistoryList> {
  late Future<List<TxItem>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = fetchHistory(widget.asset, app.addressOf(widget.asset));
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.asset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('İşlemler',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => setState(_load),
            ),
          ],
        ),
        FutureBuilder<List<TxItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('İşlem geçmişi alınamadı. Yenilemeyi dene.',
                    style: TextStyle(color: kMuted)),
              );
            }
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Henüz işlem yok.', style: TextStyle(color: kMuted)),
              );
            }
            return Column(
              children: [
                for (final t in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: kCard,
                      child: Icon(
                        t.incoming ? Icons.south_west : Icons.north_east,
                        color: t.failed ? kDown : (t.incoming ? kUp : kMuted),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      t.failed
                          ? 'Başarısız'
                          : (t.incoming ? 'Alındı' : 'Gönderildi'),
                    ),
                    subtitle: Text(
                      '${shortAddr(t.counterparty)}\n${_fmtTime(t.time)}',
                      style: const TextStyle(color: kMuted, fontSize: 12),
                    ),
                    isThreeLine: true,
                    trailing: Text(
                      '${t.incoming ? '+' : '-'}${fmtAmount(t.amount, a.decimals)} ${a.symbol}',
                      style: TextStyle(
                        color: t.incoming ? kUp : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: t.hash));
                      if (context.mounted) snack(context, 'İşlem numarası kopyalandı');
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
