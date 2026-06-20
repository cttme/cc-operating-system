---
name: commit
description: Analyze changes and create a conventional commit
allowed-tools: Bash(git *)
---

## Context
- Status: !`git status`
- Diff: !`git diff HEAD`
- Branch: !`git branch --show-current`

## Talimatlar
1. Staged ve unstaged degisiklikleri analiz et
2. Degisiklik tipini belirle:
   - Yeni dosya/ozellik → feat
   - Bug fix → fix
   - Refactor → refactor
   - Test → test
   - Dokumantasyon → docs
   - Altyapi/config → chore
3. Scope belirle: scraper, matcher, api, db, frontend, review, infra
4. Commit mesaji olustur: `<type>(<scope>): <kisa aciklama>`
5. Ilgili dosyalari stage et (`git add` — spesifik dosyalar, `git add .` degil)
6. `git commit` calistir
7. Hassas dosyalari (.env, secrets/) ASLA commit etme
