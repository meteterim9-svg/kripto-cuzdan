import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'assets.dart';
import 'screens.dart';
import 'send_api.dart';
import 'send_logic.dart';
import 'state.dart';
import 'theme.dart';

String errText(Object e) {
  if (e is StateError) return e.message;
  if (e is ApiError) return e.message;
  if (e is TimeoutException) return 'Zaman aşımı. İnternet bağlantını kontrol et.';
  if (e is FormatException) return 'Beklenmeyen yanıt alındı.';
  return 'Hata: $e';
}

/// QR veya panodan gelen metinden adresi (ve varsa tutari) ayiklar.
({String address, String? amount}) parsePayload(String raw) {
  var s = raw.trim();
  String? amount;
  final c = s.indexOf(':');
  if (c > 0) {
    final scheme = s.substring(0, c).toLowerCase();
    if (scheme == 'bitcoin' || scheme == 'ethereum' || scheme == 'tron') {
      s = s.substring(c + 1);
    }
  }
  final q = s.indexOf('?');
  if (q >= 0) {
    try {
      amount = Uri.splitQueryString(s.substring(q + 1))['amount'];
    } catch (_) {}
    s = s.substring(0, q);
  }
  for (final sep in ['@', '/']) {
    final i = s.indexOf(sep);
    if (i > 0) s = s.substring(0, i);
  }
  return (address: s, amount: amount);
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR kodu tara')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_done) return;
              for (final b in capture.barcodes) {
                final v = b.rawValue;
                if (v != null && v.isNotEmpty) {
                  _done = true;
                  Navigator.pop(context, v);
                  return;
                }
              }
            },
            errorBuilder: (context, error, child) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Kamera açılamadı. Uygulamaya kamera izni verdiğinden emin ol.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          const Align(
            alignment: Alignment(0, 0.8),
            child: Text('Alıcının QR kodunu çerçeveye getir'),
          ),
        ],
      ),
    );
  }
}

class SendScreen extends StatefulWidget {
  final Asset asset;
  const SendScreen({super.key, required this.asset});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _addr = TextEditingController();
  final _amt = TextEditingController();
  String _tier = 'normal';
  bool _max = false;
  bool _busy = false;
  String? _addrErr;
  String? _amtErr;
  String? _err;

  Asset get a => widget.asset;
  BigInt get _bal => app.balances[a.id] ?? BigInt.zero;

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text == null) return;
    _apply(d!.text!);
  }

  void _apply(String raw) {
    final p = parsePayload(raw);
    setState(() {
      _addr.text = p.address;
      _addrErr = null;
      if (p.amount != null && a.chain == Chain.btc) {
        _amt.text = p.amount!;
        _max = false;
      }
    });
  }

  Future<void> _scan() async {
    final v = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (v != null) _apply(v);
  }

  Future<void> _continue() async {
    FocusScope.of(context).unfocus();
    final addr = _addr.text.trim();
    final addrErr = validateAddress(a, addr);
    BigInt? amount;
    String? amtErr;
    if (!_max) {
      amount = parseAmount(_amt.text, a.decimals);
      if (amount == null || amount <= BigInt.zero) {
        amtErr = 'Geçerli bir tutar gir (en fazla ${a.decimals} ondalık)';
      } else if (amount > _bal) {
        amtErr = 'Bakiye yetersiz';
      }
    } else if (_bal <= BigInt.zero) {
      amtErr = 'Bakiye yok';
    }
    setState(() {
      _addrErr = addrErr;
      _amtErr = amtErr;
      _err = null;
    });
    if (addrErr != null || amtErr != null) return;

    setState(() => _busy = true);
    try {
      final tx = await prepareSend(
        asset: a,
        wallet: app.selected!,
        to: addr,
        tier: _tier,
        amount: amount,
        max: _max,
      );
      if (!mounted) return;
      final sent = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => ConfirmSendScreen(tx: tx)),
      );
      if (sent == true && mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _err = errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTiers = a.chain != Chain.trx;
    return Scaffold(
      appBar: AppBar(title: Text('${a.symbol} gönder')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Ağ: ${a.networkName}', style: const TextStyle(color: kMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: _addr,
              autocorrect: false,
              enableSuggestions: false,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Alıcı adresi',
                errorText: _addrErr,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.content_paste),
                      onPressed: _paste,
                    ),
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: _scan,
                    ),
                  ],
                ),
              ),
              onChanged: (_) => setState(() => _addrErr = null),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amt,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Tutar (${a.symbol})',
                errorText: _amtErr,
                suffixIcon: TextButton(
                  onPressed: () => setState(() {
                    _max = true;
                    _amt.text = fmtAmount(_bal, a.decimals);
                    _amtErr = null;
                  }),
                  child: const Text('Tümü'),
                ),
              ),
              onChanged: (_) => setState(() {
                _max = false;
                _amtErr = null;
              }),
            ),
            const SizedBox(height: 8),
            Text(
              'Bakiye: ${fmtAmount(_bal, a.decimals)} ${a.symbol}',
              style: const TextStyle(color: kMuted),
            ),
            if (hasTiers) ...[
              const SizedBox(height: 20),
              const Text('Ağ ücreti', style: TextStyle(color: kMuted)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'slow', label: Text('Yavaş')),
                  ButtonSegment(value: 'normal', label: Text('Normal')),
                  ButtonSegment(value: 'fast', label: Text('Hızlı')),
                ],
                selected: {_tier},
                onSelectionChanged: (s) => setState(() => _tier = s.first),
              ),
            ],
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_err!, style: const TextStyle(color: kDown)),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _continue,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Devam'),
            ),
          ],
        ),
      ),
    );
  }
}

class ConfirmSendScreen extends StatefulWidget {
  final PreparedTx tx;
  const ConfirmSendScreen({super.key, required this.tx});

  @override
  State<ConfirmSendScreen> createState() => _ConfirmSendScreenState();
}

class _ConfirmSendScreenState extends State<ConfirmSendScreen> {
  bool _sending = false;
  String? _txid;
  String? _error;

  PreparedTx get tx => widget.tx;

  Future<void> _confirm() async {
    if (!await askPin(context, title: 'Göndermek için PIN gir')) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final id = await tx.send();
      if (!mounted) return;
      setState(() => _txid = id);
      app.refresh();
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = tx.asset;
    final price = app.prices[a.cgId];
    final fiat = price == null
        ? ''
        : fmtFiat(
            toDoubleAmount(tx.amountRaw, a.decimals) * price.value(app.currency),
            app.currency);

    if (_txid != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gönderildi'), automaticallyImplyLeading: false),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, size: 80, color: kUp),
                const SizedBox(height: 16),
                Text(
                  '${fmtAmount(tx.amountRaw, a.decimals)} ${a.symbol}',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text('İşlem ağa gönderildi. Onaylanması biraz sürebilir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kMuted)),
                const SizedBox(height: 16),
                SelectableText(_txid!, textAlign: TextAlign.center),
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('İşlem numarasını kopyala'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _txid!));
                    if (context.mounted) snack(context, 'Kopyalandı');
                  },
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Tamam'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Onayla')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Text(
                '${fmtAmount(tx.amountRaw, a.decimals)} ${a.symbol}',
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
              ),
            ),
            if (fiat.isNotEmpty)
              Center(child: Text(fiat, style: const TextStyle(color: kMuted))),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Alıcı', style: TextStyle(color: kMuted)),
                    const SizedBox(height: 4),
                    SelectableText(tx.to,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    const Text('Ağ', style: TextStyle(color: kMuted)),
                    const SizedBox(height: 4),
                    Text(a.networkName),
                    const SizedBox(height: 16),
                    const Text('Ağ ücreti', style: TextStyle(color: kMuted)),
                    const SizedBox(height: 4),
                    Text(tx.feeText),
                  ],
                ),
              ),
            ),
            if (tx.warning != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(tx.warning!, style: const TextStyle(color: kMuted)),
              ),
            const SizedBox(height: 12),
            const Text(
              'Blokzincir işlemleri geri alınamaz. Adresi ve ağı bir kez daha kontrol et.',
              style: TextStyle(color: kDown),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: kDown)),
              const SizedBox(height: 8),
              const Text(
                'Sonuç belirsiz olabilir. Tekrar denemeden önce işlem geçmişini ve bakiyeni kontrol et.',
                style: TextStyle(color: kMuted),
              ),
            ],
            const SizedBox(height: 24),
            if (_error == null)
              FilledButton(
                onPressed: _sending ? null : _confirm,
                child: _sending
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Onayla ve gönder'),
              )
            else
              FilledButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Kapat'),
              ),
          ],
        ),
      ),
    );
  }
}
