---
name: session-end
description: Session kapatma — handoff'a "🎯 Next Task Brief" yaz, lessons/decisions append, rotation kontrolü. Sonraki session sadece /onboard + "evet" ile başlasın.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# /session-end — Session Kapatma Akışı

`/clear` çekmeden ÖNCE çağrılır. **Handoff'ı standart formatta günceller** ki sonraki session sadece `/onboard` + "evet" ile başlayabilsin.

## Akış (6 adım)

### Adım 1: Session Özeti

```bash
git log --oneline -10
git status --short
git diff HEAD~5..HEAD --stat 2>/dev/null | head -10
```

Kullanıcıya doğrula:
- "Bu session'da [X] yaptık. Doğru mu? Ekleme?"

### Adım 2: SIRADAKI İşi Belirle — KRİTİK ADIM

Bu kısım handoff'taki "🎯 Next Task Brief" bölümünü dolduracak. Soru sor:

```
Sıradaki iş ne?

1. Konu/madde: (örn: "S36 Sprint 2 madde 10 — Hero search header redirect")

2. Implementasyon adımları (3-5 madde):
   - Hangi dosya, ne değişikliği

3. Setup gerekli mi? (server, port, MCP, env)

4. Doğrulama kriterleri:
   - Test/lint/manuel check

Eğer "sıradaki tam belli değil" diyorsan, todo.md'nin "Aktif" section'ı
veya "Backlog"'taki ilk madde otomatik seçilir.
```

Cevabı topla. Eğer kullanıcı atlamak isterse: handoff'taki mevcut "Sıradaki" section'ı koru, brief'i basit tut.

### Adım 3 ÖN-İŞ: Eski Handoff'u Archive Et

handoff.md overwrite edilmeden ÖNCE, mevcut hâlini archive'la:

```bash
mkdir -p tasks/archive/handoffs
if [ -f tasks/handoff.md ]; then
  cp tasks/handoff.md tasks/archive/handoffs/handoff-$(date +%Y-%m-%d-%H%M).md
fi
```

Bu sayede her session'ın bittiği nokta markdown olarak tarihsel iz bırakır.
`tasks/archive/handoffs/` lazy-load (`.claudeignore`'da tasks/archive/ var) — token yükü yok.

### Adım 3: handoff.md Standart Format Yaz (overwrite)

Şu yapı zorunlu:

```markdown
# Session Handoff — [Sprint/Phase name]

> Previous sessions: `tasks/archive/`

## Environment

- **Worktree:** [path]
- **Branch:** [git branch]
- **Ports:** [if any]
- **Dev server:** [start command]
- **Pre-commit:** [tsc/pytest/lint present?]

## Completed This Session ✓

- [Item 1] (commit_hash)
- [Item 2] (commit_hash)

## 🎯 Next Task Brief

**Task:** [Topic/Item title — from Step 2]

**Budget tier:** local | Sonnet | Opus — the recommended execution tier for this task (delegate-by-default: Sonnet unless it's a one-way door or needs algo / data-integrity / architectural reasoning → Opus; trivial single-token → local).

**Implementation:**
- [Step 1 — from Step 2]
- [Step 2]
- [Step 3]

**Setup:** [from Step 2, if any]

**Verification:**
- [Check 1 — from Step 2]
- [Check 2]
- [tsc clean + pre-commit pass / pytest pass]

## Next Up (backlog, picked after brief)

- [ ] [Next item 1]
- [ ] [Next item 2]

## Discovered (out-of-scope findings)

[Any new bug/need noticed this session]

## Rules / Reminders

[Fixed ports, common gotchas — project-specific]

---

Last updated: [YYYY-MM-DD HH:MM]
```

**Target size:** <60 lines. The "🎯 Next Task Brief" section must be at least 8 lines (the next session's /onboard will read it).

> **Output language:** handoff section headers and the final summary are written in **English**. Product-facing strings stay Turkish; do not retranslate pre-existing Turkish content in older docs.

### Adım 4: Yeni Lessons Append

Bu session'da yeni öğrenilen tuzak/pattern var mı?

Use the FULL field template from `tasks/lessons.md` "## Format" block (SSOT — do not
use a shortened form). Fields as of 2026-07-03 (canary 2026-06-15 + S6 catch-ledger):

```markdown
## [YYYY-MM-DD]: [Topic]
**Error:** ... **Cause:** ... **Rule:** ...
**Caught-at:** design|review|pre-commit|test|prod|late
**Impact:** high|med|low
**Fix-type:** structural | memory
**Mechanism:** rule name | hook | doublecheck | pre-commit | test | user-report | none
**Rule-birth:** post | pre
**Severity:** trivial | rework | shipped-bug
**Count:** 1
```

`tasks/lessons.md` SONUNA **append** (overwrite yasak).

### Adım 5: Yeni Decisions Append

Mimari karar alındı mı?

```markdown
## YYYY-MM-DD: [Karar başlığı]
**Bağlam:** ...
**Alternatifler:** (A) ... (B) ... (C) ...
**Karar:** ...
**Neden:** ...
**Reversibility:** one-way | two-way
**Status:** Proposed | Accepted | Superseded
**Outcome:** PR #... | (pending)
```

`tasks/decisions.md` SONUNA append. **Reversibility** = hard-to-undo (one-way:
schema, public API, data migration) vs easy (two-way: refactor, UI, config).
One-way doors warrant backup + /verify + a /council pass (see change-protocol.md).

### Adım 6: Rotation Kontrolü

```bash
python scripts/size_guard.py 2>&1
```

Uyarı varsa kullanıcıya bildir:
- `lessons.md > 500 satır` → "Q-bazlı archive öneririm. Onaylar mısın?"
- `decisions.md > 500 satır` → "tasks/refs/'e taşıyalım. Onay?"
- `audit.md > 1000 satır` → "Eski audit'leri archive'a"

Kullanıcı onay verirse uygula. Yoksa bilgilendirme ile bırak.

### Adım 6.5: Retro Hatırlatması (cadence nudge)

`/retro` is cadence-based (milestone/quarterly) — nothing auto-fires it, so check here:

```bash
LAST=$(ls -t tasks/retro/retro-*.md 2>/dev/null | head -1)
if [ -z "$LAST" ]; then
  echo "RETRO: never run — consider /retro next session."
else
  AGE=$(( ( $(date +%s) - $(stat -c %Y "$LAST" 2>/dev/null || stat -f %m "$LAST") ) / 86400 ))
  echo "RETRO: last run ${AGE}d ago ($LAST)"
  [ "$AGE" -ge 14 ] && echo "  → ≥14d: suggest /retro next session (token/rework/kill-list review)."
fi
```

If ≥14 days (or never) **and** this session shipped a milestone → add a one-line
"consider /retro" to the handoff's Next Up. Don't force it on a trivial session.

### Adım 6.6: Routing-Quality Scorecard (R6, observational)

```bash
python scripts/routing_quality.py
```

Purely observational — replays this session's trajectory from `tasks/audit.md`
and reports whether the model tier chosen matched the work (mechanical-on-Opus
waste %, delegated calls, cheap-tier calls). **Never blocks; never gates
session-end.** Include the printed scorecard line verbatim in the session-end
summary output (Adım "Final Çıktı"). If waste % is high, note it as a lesson
candidate for Adım 4 — don't act on it unilaterally, just surface it.

## Final Çıktı

```
═══════════════════════════════════════════════════
   /session-end COMPLETE
═══════════════════════════════════════════════════
  ✓ handoff.md updated ([X] lines)
    └ "🎯 Next Task Brief" section filled ([Y] lines)
  ✓ lessons.md: +[N] new lesson(s)
  ✓ decisions.md: +[N] new decision(s)
  ✓ Rotation: [Needed / Not needed]
  ✓ Routing quality: [scorecard line from scripts/routing_quality.py]
───────────────────────────────────────────────────
  NOW:
    1. /clear
    2. New session: /onboard
    3. "yes" (or redirect/plan)
═══════════════════════════════════════════════════
```

## Kurallar

- **Append-only:** lessons.md, decisions.md
- **Overwrite OK:** handoff.md
- **🎯 Next Task Brief BOŞ KALMAMALI** — eğer kullanıcı atlasa, en azından handoff'taki "Sıradaki"den minimum bilgi al
- **Token-efficient:** head/tail, full read minimum
- **Çift kontrol:** Kullanıcıdan onay al (session özeti, sıradaki iş)

## Skip Senaryosu

- Hiçbir commit yok → sadece handoff'taki "Bu Session'da Tamamlanan" boş bırak, brief eski hâliyle kal
- Sub-5dk session → kullanıcıya "atlayalım mı?" sor, evet derse hiçbir şey yapma

## İlgili

- `/onboard` — pair skill, brief'i okur ve sunar
- `/verify` — sağlık kontrolü (opsiyonel /session-end öncesi)
- `.claude/rules/change-protocol.md` — yüksek-risk değişiklik disiplini

## Kullanım

```
/session-end
```

Skill seninle konuşur, brief'i toplar, dosyaları günceller. Bittiğinde `/clear` çekebilirsin.
