---
name: onboard
description: Yeni session orientation — handoff oku, git/todo/token kontrol, "🎯 Next Task Brief"i sun, "evet" ile başlat
allowed-tools: Read, Bash, Glob, Grep, mcp__ccd_session_mgmt__search_session_transcripts
---

# /onboard — Yeni Session Orientation

Yeni session açıldığında veya `/clear` sonrası, **minimum token ile** durumu topla VE handoff'taki Next Task Brief'i sun. Kullanıcı "evet" derse çalışmaya başla.

## Akış (6 adım)

### 0. RESUME DETECTION (KRİTİK — önce bu!)

**Auto-answers resume-vs-fresh itself** — no fallback starter file to lean on
anymore (killed, UX-P5 2026-07-03). Size alone is ambiguous: a big transcript
file can be *this* session being resumed (expensive, cache_creation tax) OR it
can be a **previous** session's leftover file that just happens to still be the
newest by mtime (harmless — this is actually a fresh session). Disambiguate with
**size + mtime age** together:

```bash
# En son aktif transcript'in boyutu VE yaşı (mtime) bul
TRANSCRIPT=$(ls -t ~/.claude/projects/*/[0-9a-f]*.jsonl 2>/dev/null | head -1)
if [ -n "$TRANSCRIPT" ]; then
  SIZE_KB=$(($(stat -c '%s' "$TRANSCRIPT" 2>/dev/null || stat -f '%z' "$TRANSCRIPT") / 1024))
  MTIME=$(stat -c '%Y' "$TRANSCRIPT" 2>/dev/null || stat -f '%m' "$TRANSCRIPT")
  AGE_SEC=$(( $(date +%s) - MTIME ))

  if [ "$SIZE_KB" -le 500 ]; then
    # Branch 1: small → fresh, proceed silently
    :
  elif [ "$AGE_SEC" -gt 600 ]; then
    # Branch 2: big but old (>10min untouched) → it's a PREVIOUS session's
    # leftover file, not this one → proceed WITHOUT asking, just note it
    echo "ℹ Newest transcript is ${SIZE_KB}KB but last touched $((AGE_SEC/60))min ago — treating as a prior session's file, proceeding fresh."
  else
    # Branch 3: big AND recent (<=10min) → ambiguous, could be THIS session
    # being resumed → only this branch asks
    echo "🚨 RESUME ALGILANDI: Transcript ${SIZE_KB}KB, ${AGE_SEC}s önce güncellendi"
    echo "   Bu fresh session DEĞİLSE, devam etmek pahalı (cache_creation tax)."
    echo "   Öneri: /session-end → /clear → yeni session aç → /onboard"
  fi
fi
```

- **Branch 1 (small, ≤500KB):** fresh, proceed silently (Adım 1'e geç) — unchanged.
- **Branch 2 (big, but mtime >~10min old):** that transcript belongs to a session
  that already closed — proceed WITHOUT asking, just print the info line above,
  then continue to Adım 1.
- **Branch 3 (big AND mtime ≤~10min):** genuinely ambiguous — this is the ONLY
  branch that stops and asks: "Bu session resume mu (eski) yoksa fresh mi
  (yeni)?" Resume ise `/session-end` + `/clear` öner; fresh ise Adım 1'e geç.

### 1. Durum Topla

```bash
# Git
git branch --show-current
git log --oneline -8
git status --short

# Handoff (öncelik)
cat tasks/handoff.md 2>/dev/null || cat handoff.md 2>/dev/null

# Aktif todo
grep -A 15 -E "^## (Aktif|Active|Şu an)" tasks/todo.md 2>/dev/null | head -20

# Token
ccusage daily 2>/dev/null | tail -6

# Aktif plan
ls -t ~/.claude/plans/*.md 2>/dev/null | head -5

# Index.md'ler
find . -maxdepth 2 -name "index.md" -not -path "*/node_modules/*" -not -path "*/.next/*" -not -path "*/archive/*" 2>/dev/null
```

### 2. Handoff'tan "🎯 Next Task Brief" Bölümünü Çıkar

`tasks/handoff.md`'de **🎯 Next Task Brief** başlığını ara, sonraki `## ` başlığına kadar oku. Bu task brief'tir.

Eğer bölüm YOK ise: "Brief boş — kullanıcıya sor" senaryosuna geç.

### 3. Özet ve Brief Sun

Aşağıdaki yapıda **kısa, scannable** çıktı ver:

```markdown
## 🔄 Onboard — [Sprint/Phase name]

### 📍 Status
- **Branch:** [branch]
- **Last commit:** [hash + short message]
- **Completed this week:** [last 5 commits, 1-line summary]

### 📊 Token usage today
[ccusage tail output, or "No data yet"]

### 🎯 Next Task (from handoff.md)

**[Task title]**

**Implementation:**
- [step 1]
- [step 2]
- [step 3]

**Setup:** [if any]

**Verification:**
- [check 1]
- [check 2]

---

▶ Shall I start this task?
  • **"yes"** → I'll plan it and begin
  • Say so if you want something else (redirect)
  • **"plan"** → I'll draft a detailed plan via /plan first
```

### 4. Cevabı Bekle — Autonomous BAŞLAMA

Skill burada **DUR ve bekle**. Kullanıcı cevap verene kadar çalışmaya başlama.

Kullanıcı:
- **"evet" / "go" / "başla"** → Task'a gir, ilk adımı yap
- **"planla"** → `/plan` skill akışına gir, detay plan üret
- **Spesifik redirect** ("aslında X yapalım") → Yeni task'a yönlen
- **Soru sorar** → Cevapla, sonra "şimdi mi başlayalım?" diye tekrar sor

### 5. Brief Yok / Boş Senaryo

`tasks/handoff.md` yoksa veya "🎯 Next Task Brief" bölümü boş ise, **kullanıcıya
sormadan ÖNCE** geçmiş session'lardan bağlam kurtarmayı dene:

1. `mcp__ccd_session_mgmt__search_session_transcripts` çağır — `query` olarak
   handoff'tan çıkardığın son sprint/branch adını veya açık görev anahtar
   kelimesini ver (örn. branch adı, "Next Task", son commit scope'u).
2. En yeni 1–2 hit'in snippet'inden bir "muhtemel sıradaki iş" çıkar.
3. Bulursan, aşağıdaki çıktıda **⚠ No Next Task Brief found** yerine
   *"Geçmiş session'dan kurtarıldı (doğrula): …"* diye **öneri** olarak sun —
   ama yine de Adım 4 kuralı geçerli: **autonomous başlama**, kullanıcı onayı bekle.
4. Hiçbir şey bulunamazsa aşağıdaki standart "sor" çıktısına geç.

> Bu, handoff.md manuel SSOT'tur; transcript search ise *sorgulanabilir* yedek.
> Aynı araç oturum içinde "geçen sefer X hakkında ne karar vermiştik?" sorularına
> da cevap verir (Tip #4 — "search past chats").

```markdown
## 🔄 Onboard — [project]

### 📍 Status
[git + token info]

### ⚠ No Next Task Brief found

handoff.md has no standard "🎯 Next Task Brief" section.
This can happen because:
- This is a new project / first session
- The previous session didn't use the /session-end skill

**What would you like to do?**
- Paste the task brief here → I'll start working
- Or let's plan new work via `/plan`
- Or update handoff.md, then run /onboard again
```

## Kurallar

- **Token-efficient:** Tüm dosyalarda Read(offset, limit). Tam dosya yasak.
- **Kısa çıktı:** Bullet/tablo, prose minimum
- **Hata yutma:** Kaynak yoksa "(yok)" yaz, sessiz geçme
- **AUTONOMOUS BAŞLAMA YASAK:** Brief'i sunarsın, bekler, "evet" alırsan başlarsın
- **Plan-first reflex:** Task 3+ adımsa "/plan ile detay" öner

## Kullanım

Yeni session başında:
```
/onboard
```

Sonra kullanıcının "evet" / "redirect" / "planla" cevabını bekle.

## İlgili

- `/session-end` — pair skill, çıkışta brief'i yazar
- `tasks/handoff.md` — single source of truth (Next Task Brief bölümü ile) — the ONLY starter mechanism (UX-P5 2026-07-03: fallback starter file killed)
- `~/.claude/plans/archive/` — historical location of the old next-session-starter.md files (dead mechanism, kept for reference only)
