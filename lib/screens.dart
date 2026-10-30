import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home.dart';
import 'vault.dart';

void snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// PIN sorar, dogruysa true doner.
Future<bool> askPin(BuildContext context, {String title = 'PIN gir'}) async {
  final ctrl = TextEditingController();
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(errorText: error, counterText: ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () async {
              final good = await Vault.verifyPin(ctrl.text);
              if (good) {
                if (ctx.mounted) Navigator.pop(ctx, true);
              } else {
                setState(() => error = 'Yanlış PIN');
              }
            },
            child: const Text('Onayla'),
          ),
        ],
      ),
    ),
  );
  return ok ?? false;
}

/// Acilista PIN durumuna gore dogru ekrani gosterir.
class Gate extends StatefulWidget {
  const Gate({super.key});

  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  bool? _hasPin;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    Vault.hasPin().then((v) {
      if (mounted) setState(() => _hasPin = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasPin == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_unlocked) return const HomeScreen();
    return PinScreen(
      setup: !_hasPin!,
      onDone: () => setState(() {
        _hasPin = true;
        _unlocked = true;
      }),
    );
  }
}

class PinScreen extends StatefulWidget {
  final bool setup;
  final VoidCallback onDone;
  const PinScreen({super.key, required this.setup, required this.onDone});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  final _ctrl = TextEditingController();
  String? _first;
  String? _error;
  int _fails = 0;
  bool _busy = false;

  Future<void> _submit() async {
    final pin = _ctrl.text;
    if (pin.length != 6) {
      setState(() => _error = 'PIN 6 haneli olmalı');
      return;
    }
    setState(() => _busy = true);
    if (widget.setup) {
      if (_first == null) {
        setState(() {
          _first = pin;
          _ctrl.clear();
          _error = null;
          _busy = false;
        });
        return;
      }
      if (_first != pin) {
        setState(() {
          _first = null;
          _ctrl.clear();
          _error = 'PIN\'ler uyuşmadı, baştan dene';
          _busy = false;
        });
        return;
      }
      await Vault.setPin(pin);
      widget.onDone();
    } else {
      final ok = await Vault.verifyPin(pin);
      if (ok) {
        widget.onDone();
      } else {
        _fails++;
        setState(() {
          _ctrl.clear();
          _error = 'Yanlış PIN ($_fails)';
          _busy = false;
        });
        if (_fails >= 5) {
          // Basit bekleme: 5 yanlis denemeden sonra 30 sn kilit.
          setState(() => _busy = true);
          await Future<void>.delayed(const Duration(seconds: 30));
          if (!mounted) return;
          setState(() {
            _fails = 0;
            _busy = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.setup
        ? (_first == null ? 'PIN oluştur' : 'PIN\'i tekrar gir')
        : 'Kilidi aç';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 24),
              TextField(
                controller: _ctrl,
                enabled: !_busy,
                autofocus: true,
                obscureText: true,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 28, letterSpacing: 12),
                decoration:
                    InputDecoration(errorText: _error, counterText: ''),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(widget.setup ? 'Devam' : 'Aç'),
              ),
              if (_fails >= 5)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('Çok fazla deneme, 30 saniye bekle.'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Yeni cuzdan olusturma veya seed ile geri yukleme.
class WalletFormScreen extends StatefulWidget {
  final bool restore;
  const WalletFormScreen({super.key, required this.restore});

  @override
  State<WalletFormScreen> createState() => _WalletFormScreenState();
}

class _WalletFormScreenState extends State<WalletFormScreen> {
  final _name = TextEditingController(text: 'Cüzdan');
  final _seedCtrl = TextEditingController();
  late final String _generated =
      widget.restore ? '' : bip39.generateMnemonic();
  bool _written = false;
  String? _error;

  Future<void> _save() async {
    final name = _name.text.trim().isEmpty ? 'Cüzdan' : _name.text.trim();
    String mnemonic;
    if (widget.restore) {
      mnemonic = _seedCtrl.text.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
      if (!bip39.validateMnemonic(mnemonic)) {
        setState(() => _error = 'Geçersiz seed. Kelimeleri ve sırayı kontrol et.');
        return;
      }
    } else {
      mnemonic = _generated;
    }
    final wallets = await Vault.loadWallets();
    wallets.add(Wallet(id: Vault.newId(), name: name, mnemonic: mnemonic));
    await Vault.saveWallets(wallets);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final words = _generated.isEmpty ? <String>[] : _generated.split(' ');
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.restore ? 'Cüzdanı geri yükle' : 'Yeni cüzdan'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Cüzdan adı'),
          ),
          const SizedBox(height: 16),
          if (widget.restore) ...[
            TextField(
              controller: _seedCtrl,
              minLines: 3,
              maxLines: 5,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '12 veya 24 kelimelik seed',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
          ] else ...[
            const Text(
              'Bu 12 kelime cüzdanının tek yedeğidir. Kâğıda sırayla yaz, '
              'kimseyle paylaşma, ekran görüntüsü alma. Kaybedersen paraya '
              'bir daha erişemezsin.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < words.length; i++)
                  Chip(label: Text('${i + 1}. ${words[i]}')),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _written,
              onChanged: (v) => setState(() => _written = v ?? false),
              title: const Text('Kelimeleri güvenli bir yere yazdım'),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: (widget.restore || _written) ? _save : null,
            child: Text(widget.restore ? 'Geri yükle' : 'Cüzdanı oluştur'),
          ),
        ],
      ),
    );
  }
}
