import 'package:flutter/foundation.dart';

import 'api.dart';
import 'assets.dart';
import 'chains.dart';
import 'vault.dart';

/// Uygulamanin ortak durumu: cuzdanlar, secili cuzdan, bakiyeler, fiyatlar.
class AppState extends ChangeNotifier {
  List<Wallet> wallets = [];
  String? selectedId;
  String currency = 'usd';
  Map<String, BigInt> balances = {};
  Map<String, Price> prices = {};
  bool loading = false;
  bool loaded = false;
  String? error;
  final Map<String, ChainAddresses> _addrCache = {};

  Wallet? get selected {
    for (final w in wallets) {
      if (w.id == selectedId) return w;
    }
    return null;
  }

  ChainAddresses? get addresses {
    final w = selected;
    if (w == null) return null;
    return _addrCache.putIfAbsent(w.id, () => addressesFor(w.mnemonic));
  }

  String addressOf(Asset a) {
    final ad = addresses!;
    switch (a.chain) {
      case Chain.btc:
        return ad.btc;
      case Chain.eth:
        return ad.eth;
      case Chain.trx:
        return ad.trx;
    }
  }

  double fiatOf(Asset a) {
    final bal = balances[a.id];
    final price = prices[a.cgId];
    if (bal == null || price == null) return 0;
    return toDoubleAmount(bal, a.decimals) * price.value(currency);
  }

  double get totalFiat => allAssets.fold(0.0, (sum, a) => sum + fiatOf(a));

  Future<void> init() async {
    wallets = await Vault.loadWallets();
    selectedId = await Vault.getSelected();
    currency = await Vault.getCurrency();
    if (selected == null && wallets.isNotEmpty) {
      selectedId = wallets.first.id;
      await Vault.setSelected(selectedId!);
    }
    loaded = true;
    notifyListeners();
    refresh();
  }

  Future<void> reloadWallets({bool selectLast = false}) async {
    wallets = await Vault.loadWallets();
    if (wallets.isEmpty) {
      selectedId = null;
    } else if (selectLast) {
      selectedId = wallets.last.id;
      await Vault.setSelected(selectedId!);
    } else if (selected == null) {
      selectedId = wallets.first.id;
      await Vault.setSelected(selectedId!);
    }
    balances = {};
    notifyListeners();
    refresh();
  }

  Future<void> select(String id) async {
    selectedId = id;
    await Vault.setSelected(id);
    balances = {};
    notifyListeners();
    refresh();
  }

  Future<void> setCurrency(String c) async {
    currency = c;
    await Vault.setCurrency(c);
    notifyListeners();
  }

  Future<void> refresh() async {
    final ad = addresses;
    if (ad == null) return;
    final forId = selectedId;
    loading = true;
    error = null;
    notifyListeners();

    final b = await Api.balances(ad);
    final p = await Api.prices();

    if (forId != selectedId) return; // bu arada baska cuzdana gecildi
    balances = {...balances, ...b};
    if (p.isNotEmpty) prices = p;
    if (b.length < allAssets.length || p.isEmpty) {
      error = 'Bazı veriler alınamadı. Çekip bırakarak yenile.';
    }
    loading = false;
    notifyListeners();
  }
}

final app = AppState();
