import 'dart:math';

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home.dart';
import 'platform.dart';
import 'theme.dart';
import 'vault.dart';

final navigatorKey = GlobalKey<NavigatorState>();

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
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
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

/// Acilista PIN durumuna gore dogru ekrani gosterir; arka plandan
/// donuste (ayarlanan sureden sonra) uygulamayi tekrar kilitler.
class Gate extends StatefulWidget {
  const Gate({super.key});

  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> with WidgetsBindingObserver {
  bool? _hasPin;
  bool _unlocked = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  Future<void> _boot() async {
    ScreenSecurity.set(await Vault.getSecure());
    final v = await Vault.hasPin();
    if (mounted) setState(() => _hasPin = v);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _checkLock();
    }
  }

  Future<void> _checkLock() async {
    final p = _pausedAt;
    _pausedAt = null;
    if (p == null || !_unlocked) return;
    final delay = await Vault.getLockDelay();
    if (DateTime.now().difference(p).inSeconds >= delay) {
      navigatorKey.currentState?.popUntil((r) => r.isFirst);
      if (mounted) setState(() => _unlocked = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasPin == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_unlocked) return const HomeScreen();
    return PinScreen(
      key: ValueKey('pin-${_hasPin!}'),
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
  bool _bioReady = false;

  @override
  void initState() {
    super.initState();
    if (!widget.setup) _initBio();
  }

  Future<void> _initBio() async {
    if (!await Vault.getBio()) return;
    if (!await Bio.available()) return;
    if (!mounted) return;
    setState(() => _bioReady = true);
    _tryBio();
  }

  Future<void> _tryBio() async {
    final ok = await Bio.authenticate('Orvexa kilidini aç');
    if (ok && mounted) widget.onDone();
  }

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
          // 5 yanlis denemeden sonra 30 sn bekleme.
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
              const Icon(Icons.lock_outline, size: 64, color: kAccent),
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
              if (_bioReady)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextButton.icon(
                    onPressed: _tryBio,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Parmak izi ile aç'),
                  ),
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

/// Yeni cuzdan olusturma (seed dogrulama testi ile) veya seed ile geri yukleme.
class WalletFormScreen extends StatefulWidget {
  final bool restore;
  const WalletFormScreen({super.key, required this.restore});

  @override
  State<WalletFormScreen> createState() => _WalletFormScreenState();
}

class _WalletFormScreenState extends State<WalletFormScreen> {
  final _name = TextEditingController(text: 'Cüzdan');
  final _seedCtrl = TextEditingController();
  int _wordCount = 12;
  late String _generated =
      widget.restore ? '' : bip39.generateMnemonic(strength: 128);
  bool _written = false;
  bool _quiz = false;
  List<int> _quizIdx = [];
  final List<TextEditingController> _quizCtrls = [];
  String? _nameError;
  String? _seedError;
  String? _quizError;

  @override
  void initState() {
    super.initState();
    _suggestName();
  }

  Future<void> _suggestName() async {
    final wallets = await Vault.loadWallets();
    var i = 1;
    while (Vault.nameTaken(wallets, 'Cüzdan $i')) {
      i++;
    }
    if (mounted) _name.text = 'Cüzdan $i';
  }

  void _setWordCount(int n) {
    setState(() {
      _wordCount = n;
      _generated = bip39.generateMnemonic(strength: n == 24 ? 256 : 128);
      _written = false;
    });
  }

  Future<bool> _nameOk() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Bir ad gir');
      return false;
    }
    final wallets = await Vault.loadWallets();
    if (Vault.nameTaken(wallets, name)) {
      setState(() => _nameError = 'Bu isimde bir cüzdan zaten var');
      return false;
    }
    setState(() => _nameError = null);
    return true;
  }

  Future<void> _save(String mnemonic) async {
    final wallets = await Vault.loadWallets();
    final name = _name.text.trim();
    if (Vault.nameTaken(wallets, name)) {
      setState(() {
        _quiz = false;
        _nameError = 'Bu isimde bir cüzdan zaten var';
      });
      return;
    }
    if (wallets.any((w) => w.mnemonic == mnemonic)) {
      setState(() => _seedError = 'Bu cüzdan zaten ekli');
      return;
    }
    wallets.add(Wallet(id: Vault.newId(), name: name, mnemonic: mnemonic));
    await Vault.saveWallets(wallets);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _restore() async {
    if (!await _nameOk()) return;
    final mnemonic =
        _seedCtrl.text.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
    if (!bip39.validateMnemonic(mnemonic)) {
      setState(() => _seedError = 'Geçersiz seed. Kelimeleri ve sırayı kontrol et.');
      return;
    }
    await _save(mnemonic);
  }

  Future<void> _startQuiz() async {
    if (!await _nameOk()) return;
    final rnd = Random.secure();
    final idx = <int>{};
    final total = _generated.split(' ').length;
    while (idx.length < 3) {
      idx.add(rnd.nextInt(total));
    }
    _quizIdx = idx.toList()..sort();
    _quizCtrls
      ..clear()
      ..addAll(List.generate(3, (_) => TextEditingController()));
    setState(() {
      _quiz = true;
      _quizError = null;
    });
  }

  Future<void> _checkQuiz() async {
    final words = _generated.split(' ');
    for (var i = 0; i < 3; i++) {
      if (_quizCtrls[i].text.trim().toLowerCase() != words[_quizIdx[i]]) {
        setState(() => _quizError = 'Kelimeler uyuşmuyor. Yedeğine tekrar bak.');
        return;
      }
    }
    await _save(_generated);
  }

  @override
  Widget build(BuildContext context) {
    if (_quiz) return _buildQuiz(context);
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
            decoration: InputDecoration(
              labelText: 'Cüzdan adı',
              errorText: _nameError,
            ),
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
                errorText: _seedError,
              ),
            ),
          ] else ...[
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 12, label: Text('12 kelime')),
                ButtonSegment(value: 24, label: Text('24 kelime')),
              ],
              selected: {_wordCount},
              onSelectionChanged: (s) => _setWordCount(s.first),
            ),
            const SizedBox(height: 16),
            const Text(
              'Bu kelimeler cüzdanının tek yedeğidir. Kâğıda sırayla yaz, '
              'kimseyle paylaşma. Kaybedersen paraya bir daha erişemezsin.',
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
            onPressed: widget.restore
                ? _restore
                : (_written ? _startQuiz : null),
            child: Text(widget.restore ? 'Geri yükle' : 'Devam'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuiz(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yedeği doğrula'),
        leading: BackButton(onPressed: () => setState(() => _quiz = false)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Yedeği doğru yazdığından emin olmak için aşağıdaki sıradaki '
            'kelimeleri gir.',
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _quizCtrls[i],
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: '${_quizIdx[i] + 1}. kelime',
                ),
              ),
            ),
          if (_quizError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child:
                  Text(_quizError!, style: const TextStyle(color: kDown)),
            ),
          if (_seedError != null)
            Text(_seedError!, style: const TextStyle(color: kDown)),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _checkQuiz,
            child: const Text('Cüzdanı oluştur'),
          ),
        ],
      ),
    );
  }
}
