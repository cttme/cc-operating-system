---
name: review
description: Review code changes against project standards — applies the scraper-reviewer / architect checklists and the no-silent-failure / no-debug-print / no-hardcoded-secret rules, returns APPROVE / REQUEST_CHANGES / REJECT. For the working diff use /code-review.
allowed-tools: Read, Grep, Glob, Bash(git *)
---

# /review — Code Review Against Project Standards

## Scope

Review the file(s) named in the invocation, or — if none given — the current
`git diff` (run `git diff HEAD` via Bash to see it).

## Talimatlar

1. Scraper kodu ise `@scraper-reviewer` agent kontrol listesini uygula:
   - `BaseScraper`'dan miras alıyor mu?
   - Selector'lar sınıf başında sabit mi?
   - Rate limiting aktif mi? (min 2 saniye)
   - Hata loglama var mı?
   - Fixture testi yazılmış mı?

2. Mimari değişiklik ise `@architect` agent ile değerlendir:
   - DB şema değişikliği var mı?
   - Performans etkisi var mı?
   - Bağımlılıklarda değişiklik var mı?

3. Genel kontrol listesi:
   - `except Exception: pass` var mı? → REDDET
   - `print()` debug amaçlı mı? → logger kullan
   - Hardcoded URL/selector var mı? → sabit tanımla
   - `.env` veya `secrets`'a dokunulmuş mu? → REDDET
   - `tasks/lessons.md`'deki derslerle çelişiyor mu?

4. Sonuç: **APPROVE / REQUEST_CHANGES / REJECT** (her bulguya `file:line` kanıtı ekle).
