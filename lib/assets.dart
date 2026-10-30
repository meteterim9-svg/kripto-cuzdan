import 'package:flutter/material.dart';

enum Chain { btc, eth, trx }

class Asset {
  final String id;
  final String name;
  final String symbol;
  final String networkName;
  final Chain chain;
  final int decimals;
  final String cgId; // CoinGecko kimligi
  final String? contract;
  final Color color;

  const Asset({
    required this.id,
    required this.name,
    required this.symbol,
    required this.networkName,
    required this.chain,
    required this.decimals,
    required this.cgId,
    required this.color,
    this.contract,
  });
}

const usdtEthContract = '0xdAC17F958D2ee523a2206206994597C13D831ec7';
const usdtTrxContract = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';

const allAssets = <Asset>[
  Asset(
    id: 'btc',
    name: 'Bitcoin',
    symbol: 'BTC',
    networkName: 'Bitcoin',
    chain: Chain.btc,
    decimals: 8,
    cgId: 'bitcoin',
    color: Color(0xFFF7931A),
  ),
  Asset(
    id: 'eth',
    name: 'Ethereum',
    symbol: 'ETH',
    networkName: 'Ethereum (ERC-20)',
    chain: Chain.eth,
    decimals: 18,
    cgId: 'ethereum',
    color: Color(0xFF627EEA),
  ),
  Asset(
    id: 'usdt_eth',
    name: 'Tether',
    symbol: 'USDT',
    networkName: 'Ethereum (ERC-20)',
    chain: Chain.eth,
    decimals: 6,
    cgId: 'tether',
    color: Color(0xFF26A17B),
    contract: usdtEthContract,
  ),
  Asset(
    id: 'trx',
    name: 'Tron',
    symbol: 'TRX',
    networkName: 'Tron (TRC-20)',
    chain: Chain.trx,
    decimals: 6,
    cgId: 'tron',
    color: Color(0xFFEB0029),
  ),
  Asset(
    id: 'usdt_trx',
    name: 'Tether',
    symbol: 'USDT',
    networkName: 'Tron (TRC-20)',
    chain: Chain.trx,
    decimals: 6,
    cgId: 'tether',
    color: Color(0xFF26A17B),
    contract: usdtTrxContract,
  ),
];

/// Ham (en kucuk birim) tutari okunabilir metne cevirir.
String fmtAmount(BigInt raw, int decimals) {
  if (raw == BigInt.zero) return '0';
  final s = raw.toString().padLeft(decimals + 1, '0');
  final intPart = s.substring(0, s.length - decimals);
  var frac = s.substring(s.length - decimals);
  if (frac.length > 8) frac = frac.substring(0, 8);
  frac = frac.replaceFirst(RegExp(r'0+$'), '');
  return frac.isEmpty ? intPart : '$intPart.$frac';
}

double toDoubleAmount(BigInt raw, int decimals) {
  final s = raw.toString().padLeft(decimals + 1, '0');
  final intPart = s.substring(0, s.length - decimals);
  final frac = s.substring(s.length - decimals);
  return double.parse('$intPart.$frac');
}

String fmtFiat(double v, String cur) {
  final sym = cur == 'try' ? '₺' : '\$';
  final parts = v.toStringAsFixed(2).split('.');
  final ip = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );
  return '$sym$ip.${parts[1]}';
}
