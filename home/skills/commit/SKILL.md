---
name: commit
description: Analyze the working tree and create a well-scoped conventional commit. Gathers git state via the Bash tool, picks type/scope, stages specific files (never `git add .`), and commits. Never commits .env/secrets.
allowed-tools: Bash(git *)
---

# /commit — Conventional Commit

## Gather state first

Run these via the Bash tool (this skill has no template pre-injection — read the
live state yourself):

- `git status`
- `git diff HEAD`
- `git branch --show-current`

## Talimatlar

1. Staged ve unstaged değişiklikleri analiz et.
2. Değişiklik tipini belirle:
   - Yeni dosya/özellik → `feat`
   - Bug fix → `fix`
   - Refactor → `refactor`
   - Test → `test`
   - Dokümantasyon → `docs`
   - Altyapı/config → `chore`
3. Scope belirle: scraper, matcher, api, db, frontend, review, infra.
4. Commit mesajı oluştur: `<type>(<scope>): <kısa açıklama>` (conventional).
5. İlgili dosyaları stage et (`git add` — **spesifik dosyalar, `git add .` değil**).
6. `git commit` çalıştır.
7. Hassas dosyaları (`.env`, `secrets/`) **ASLA** commit etme.
