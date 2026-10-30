import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'assets.dart';
import 'platform.dart';
import 'screens.dart';
import 'state.dart';
import 'theme.dart';
import 'vault.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    app.init();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (!app.loaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          body: _tab == 0 ? const PortfolioPage() : const SettingsPage(),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: 'Cüzdan',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Ayarlar',
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> addWalletFlow(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('Yeni cüzdan oluştur'),
            onTap: () => Navigator.pop(ctx, 'create'),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Mevcut cüzdanı geri yükle'),
            onTap: () => Navigator.pop(ctx, 'import'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final created = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => WalletFormScreen(restore: choice == 'import'),
    ),
  );
  if (created == true) await app.reloadWallets(selectLast: true);
}

// ------------------------------------------------------------------
// Varliklar sayfasi
// ------------------------------------------------------------------

class PortfolioPage extends StatelessWidget {
  const PortfolioPage({super.key});

  @override
  Widget build(BuildContext context) {
    final w = app.selected;
    if (w == null) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 72, color: kAccent),
                const SizedBox(height: 16),
                Text('Cüzdan yok',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => addWalletFlow(context),
                  child: const Text('Cüzdan ekle'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: app.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: ActionChip(
                avatar: const Icon(Icons.account_balance_wallet, size: 18),
                label: Text(w.name),
                onPressed: () => _pickWallet(context),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                fmtFiat(app.totalFiat, app.currency),
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                app.loading ? 'Güncelleniyor…' : 'Toplam bakiye',
                style: const TextStyle(color: kMuted),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundAction(
                  icon: Icons.south_west,
                  label: 'Al',
                  onTap: () => _chooseAssetToReceive(context),
                ),
                const SizedBox(width: 32),
                _RoundAction(
                  icon: Icons.refresh,
                  label: 'Yenile',
                  onTap: app.refresh,
                ),
              ],
            ),
            if (app.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  app.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kDown),
                ),
              ),
            const SizedBox(height: 24),
            for (final a in allAssets) _AssetRow(asset: a),
          ],
        ),
      ),
    );
  }

  void _pickWallet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final w in app.wallets)
              ListTile(
                leading: Icon(
                  w.id == app.selectedId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: kAccent,
                ),
                title: Text(w.name),
                onTap: () {
                  Navigator.pop(ctx);
                  app.select(w.id);
                },
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Cüzdan ekle'),
              onTap: () {
                Navigator.pop(ctx);
                addWalletFlow(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _chooseAssetToReceive(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Hangi varlığı almak istiyorsun?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            for (final a in allAssets)
              ListTile(
                leading: _AssetIcon(asset: a),
                title: Text(a.symbol),
                subtitle: Text(a.networkName),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ReceiveScreen(asset: a)),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RoundAction(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkResponse(
          onTap: onTap,
          radius: 36,
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: kAccent,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: kMuted)),
      ],
    );
  }
}

class _AssetIcon extends StatelessWidget {
  final Asset asset;
  final double size;
  const _AssetIcon({required this.asset, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: asset.color, shape: BoxShape.circle),
      child: Text(
        asset.symbol.substring(0, 1),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  final Asset asset;
  const _AssetRow({required this.asset});

  @override
  Widget build(BuildContext context) {
    final price = app.prices[asset.cgId];
    final bal = app.balances[asset.id];
    final change = price?.change(app.currency) ?? 0;
    final subtitle = price == null
        ? asset.networkName
        : '${fmtFiat(price.value(app.currency), app.currency)}  '
            '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AssetScreen(asset: asset)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            _AssetIcon(asset: asset),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(asset.symbol,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      if (asset.contract != null)
                        Text(
                          asset.chain == Chain.eth ? 'ERC-20' : 'TRC-20',
                          style: const TextStyle(color: kMuted, fontSize: 12),
                        ),
                    ],
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: price == null
                          ? kMuted
                          : (change >= 0 ? kUp : kDown),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  bal == null ? '—' : fmtAmount(bal, asset.decimals),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                Text(
                  fmtFiat(app.fiatOf(asset), app.currency),
                  style: const TextStyle(color: kMuted, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Varlik detayi ve alma ekrani
// ------------------------------------------------------------------

class AssetScreen extends StatelessWidget {
  final Asset asset;
  const AssetScreen({super.key, required this.asset});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final price = app.prices[asset.cgId];
        final bal = app.balances[asset.id];
        final change = price?.change(app.currency) ?? 0;
        return Scaffold(
          appBar: AppBar(title: Text(asset.symbol)),
          body: RefreshIndicator(
            onRefresh: app.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 8),
                Center(child: _AssetIcon(asset: asset, size: 64)),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    '${bal == null ? '—' : fmtAmount(bal, asset.decimals)} '
                    '${asset.symbol}',
                    style: const TextStyle(
                        fontSize: 32, fontWeight: FontWeight.w700),
                  ),
                ),
                Center(
                  child: Text(
                    fmtFiat(app.fiatOf(asset), app.currency),
                    style: const TextStyle(color: kMuted, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _kv('Ağ', asset.networkName),
                        const SizedBox(height: 12),
                        _kv(
                          'Fiyat',
                          price == null
                              ? '—'
                              : fmtFiat(price.value(app.currency), app.currency),
                        ),
                        const SizedBox(height: 12),
                        _kv(
                          '24 saat',
                          price == null
                              ? '—'
                              : '${change >= 0 ? '+' : ''}'
                                  '${change.toStringAsFixed(2)}%',
                          color: change >= 0 ? kUp : kDown,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.south_west),
                  label: const Text('Al'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ReceiveScreen(asset: asset)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v, {Color? color}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(color: kMuted)),
          Text(v, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      );
}

class ReceiveScreen extends StatelessWidget {
  final Asset asset;
  const ReceiveScreen({super.key, required this.asset});

  @override
  Widget build(BuildContext context) {
    final address = app.addressOf(asset);
    return Scaffold(
      appBar: AppBar(title: Text('${asset.symbol} al')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: QrImageView(
                  data: address,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '${asset.name} (${asset.networkName}) adresin',
              textAlign: TextAlign.center,
              style: const TextStyle(color: kMuted),
            ),
            const SizedBox(height: 8),
            SelectableText(
              address,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Adresi kopyala'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: address));
                if (context.mounted) snack(context, 'Adres kopyalandı');
              },
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Bu adrese sadece ${asset.networkName} ağındaki '
                  '${asset.symbol} gönder. Başka ağdan veya başka bir '
                  'varlık gönderirsen kaybedebilirsin.',
                  style: const TextStyle(color: kMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Ayarlar
// ------------------------------------------------------------------

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Ayarlar',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          ),
          const _SectionTitle('Cüzdanlar'),
          Card(
            child: Column(
              children: [
                for (final w in app.wallets)
                  ListTile(
                    leading: Icon(
                      w.id == app.selectedId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: kAccent,
                    ),
                    title: Text(w.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ManageWalletScreen(walletId: w.id),
                      ),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Cüzdan ekle'),
                  onTap: () => addWalletFlow(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('Tercihler'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.attach_money),
              title: const Text('Para birimi'),
              trailing: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'usd', label: Text('USD')),
                  ButtonSegment(value: 'try', label: Text('TRY')),
                ],
                selected: {app.currency},
                onSelectionChanged: (s) => app.setCurrency(s.first),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('Güvenlik'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.pin_outlined),
                  title: const Text('PIN değiştir'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _changePin(context),
                ),
                const _SecuritySettings(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changePin(BuildContext context) async {
    if (!await askPin(context, title: 'Mevcut PIN')) return;
    if (!context.mounted) return;
    final ctrl = TextEditingController();
    final ctrl2 = TextEditingController();
    String? error;
    final newPin = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Yeni PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    labelText: 'Yeni PIN (6 hane)', counterText: ''),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl2,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                    labelText: 'Tekrar', counterText: '', errorText: error),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
              onPressed: () {
                if (ctrl.text.length != 6) {
                  setState(() => error = 'PIN 6 haneli olmalı');
                } else if (ctrl.text != ctrl2.text) {
                  setState(() => error = 'PIN\'ler uyuşmuyor');
                } else {
                  Navigator.pop(ctx, ctrl.text);
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (newPin == null) return;
    await Vault.setPin(newPin);
    if (context.mounted) snack(context, 'PIN değiştirildi');
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(text, style: const TextStyle(color: kMuted)),
      );
}

class ManageWalletScreen extends StatefulWidget {
  final String walletId;
  const ManageWalletScreen({super.key, required this.walletId});

  @override
  State<ManageWalletScreen> createState() => _ManageWalletScreenState();
}

class _ManageWalletScreenState extends State<ManageWalletScreen> {
  Wallet? get _wallet {
    for (final w in app.wallets) {
      if (w.id == widget.walletId) return w;
    }
    return null;
  }

  Future<void> _rename() async {
    final w = _wallet;
    if (w == null) return;
    final ctrl = TextEditingController(text: w.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeniden adlandır'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final all = await Vault.loadWallets();
    if (Vault.nameTaken(all, name, exceptId: w.id)) {
      if (mounted) snack(context, 'Bu isimde bir cüzdan zaten var');
      return;
    }
    final idx = all.indexWhere((x) => x.id == w.id);
    if (idx < 0) return;
    all[idx] = all[idx].copyWith(name: name);
    await Vault.saveWallets(all);
    await app.reloadWallets();
    if (mounted) setState(() {});
  }

  Future<void> _showSeed() async {
    final w = _wallet;
    if (w == null) return;
    if (!await askPin(context, title: 'Seed için PIN gir')) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seed kelimelerin'),
        content: SelectableText(w.mnemonic),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete() async {
    final w = _wallet;
    if (w == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cüzdan silinsin mi?'),
        content: const Text(
          'Seed kelimelerini yedeklemediysen bu cüzdana ve içindeki paraya '
          'bir daha erişemezsin. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(100, 44),
              backgroundColor: kDown,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    if (!await askPin(context, title: 'Silmek için PIN gir')) return;
    final all = await Vault.loadWallets();
    all.removeWhere((x) => x.id == w.id);
    await Vault.saveWallets(all);
    await app.reloadWallets();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final w = _wallet;
    return Scaffold(
      appBar: AppBar(title: Text(w?.name ?? 'Cüzdan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                if (w != null && w.id != app.selectedId)
                  ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: const Text('Bu cüzdanı kullan'),
                    onTap: () async {
                      await app.select(w.id);
                      if (mounted) setState(() {});
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Yeniden adlandır'),
                  onTap: _rename,
                ),
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('Seed kelimelerini göster'),
                  onTap: _showSeed,
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: kDown),
                  title: const Text('Cüzdanı sil',
                      style: TextStyle(color: kDown)),
                  onTap: _delete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _SecuritySettings extends StatefulWidget {
  const _SecuritySettings();

  @override
  State<_SecuritySettings> createState() => _SecuritySettingsState();
}

class _SecuritySettingsState extends State<_SecuritySettings> {
  bool _bio = false;
  bool _secure = true;
  int _delay = 30;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await Vault.getBio();
    final s = await Vault.getSecure();
    final d = await Vault.getLockDelay();
    if (mounted) {
      setState(() {
        _bio = b;
        _secure = s;
        _delay = d;
        _ready = true;
      });
    }
  }

  Future<void> _toggleBio(bool on) async {
    if (on) {
      if (!await Bio.available()) {
        if (mounted) {
          snack(context, 'Cihazda kayıtlı parmak izi/yüz yok. Önce telefon ayarlarından ekle.');
        }
        return;
      }
      if (!await Bio.authenticate('Biyometrik kilidi etkinleştir')) return;
    }
    await Vault.setBio(on);
    if (mounted) setState(() => _bio = on);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.fingerprint),
          title: const Text('Parmak izi / yüz ile aç'),
          value: _bio,
          onChanged: _toggleBio,
        ),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Otomatik kilit'),
          trailing: DropdownButton<int>(
            value: _delay,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Hemen')),
              DropdownMenuItem(value: 30, child: Text('30 saniye')),
              DropdownMenuItem(value: 60, child: Text('1 dakika')),
              DropdownMenuItem(value: 300, child: Text('5 dakika')),
            ],
            onChanged: (v) async {
              if (v == null) return;
              await Vault.setLockDelay(v);
              setState(() => _delay = v);
            },
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.screenshot_outlined),
          title: const Text('Ekran görüntüsünü engelle'),
          subtitle: const Text('Ekran kaydı ve son uygulamalar önizlemesi de gizlenir'),
          value: _secure,
          onChanged: (v) async {
            await Vault.setSecure(v);
            await ScreenSecurity.set(v);
            setState(() => _secure = v);
          },
        ),
      ],
    );
  }
}
