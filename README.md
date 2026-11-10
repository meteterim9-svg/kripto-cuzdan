# kripto-cuzdan

Bitcoin, Ethereum, Tron ve Monero hedefleyen, anahtarlari kullanicida kalan (non-custodial) Android cuzdan. Flutter ile yazildi.

## Durum (v0.1.1)
- PIN ile kilit (Android Keystore destekli sifreli depo, PBKDF2)
- Kalici deneme kilidi: 5 yanlis PIN'den sonra 30 sn, sonraki her hatada iki kati (en fazla 1 saat). Uygulamayi kapatip acmak kilidi sifirlamaz; PIN soran tum diyaloglarda gecerli.
- Cuzdan olusturma (12/24 kelime BIP39 seed), seed ile geri yukleme
- Cuzdan yeniden adlandirma, seed gosterme (PIN ister), silme (PIN ister)
- BTC / ETH / TRX ve USDT bakiye ve fiyat gosterimi

## APK nasil alinir
GitHub > Releases > en son "Derleme N" > `orvexa.apk`.
Ya da: Actions > "APK derle" > son calisma > Artifacts > `kripto-cuzdan-apk`.

> Gercek para koymadan once bagimsiz guvenlik denetimi yaptirin.
