---
name: plan
description: Create a structured implementation plan before coding
allowed-tools: Read, Write, Grep, Glob
---

## Talimatlar

$ARGUMENTS icin yapilandirilmis uygulama plani olustur:

1. Kullanicinin talebini anla
2. Mevcut kodu kesfet (Glob + Grep + Read ile)
3. Ilgili dosyalari listele
4. Uygulama adimlari yaz:
   - Hangi dosyalar degisecek
   - Hangi yeni dosyalar olusacak
   - Hangi testler yazilacak
   - Hangi migration gerekecek
5. Risk analizi yap (breaking change, veri kaybi, performans)
6. Plani tasks/todo.md'ye ekle
7. Plani sun, onay bekle — onaysiz uygulamaya basla
