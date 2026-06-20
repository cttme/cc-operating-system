---
name: review
description: Review code changes against project standards
allowed-tools: Read, Grep, Glob
---

## Talimatlar

$ARGUMENTS dosyasini veya `git diff` ciktisini incele:

1. Scraper kodu ise @scraper-reviewer agent kontrol listesini uygula:
   - BaseScraper'dan miras aliyor mu?
   - Selector'lar sinif basinda sabit mi?
   - Rate limiting aktif mi? (min 2 saniye)
   - Hata loglama var mi?
   - Fixture testi yazilmis mi?

2. Mimari degisiklik ise @architect agent ile degerlendir:
   - DB sema degisikligi var mi?
   - Performans etkisi var mi?
   - Bagimliliklarda degisiklik var mi?

3. Genel kontrol listesi:
   - `except Exception: pass` var mi? → REDDET
   - `print()` debug amacli mi? → logger kullan
   - Hardcoded URL/selector var mi? → sabit tanimla
   - .env veya secrets'a dokunulmus mu? → REDDET
   - tasks/lessons.md'deki derslerle celisiyor mu?

4. Sonuc: APPROVE / REQUEST_CHANGES / REJECT
