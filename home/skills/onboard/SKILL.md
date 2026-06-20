---
name: onboard
description: Yeni session orientation — handoff oku, git/todo/token kontrol, "🎯 Next Task Brief"i sun, "evet" ile başlat
allowed-tools: Read, Bash, Glob, Grep, mcp__ccd_session_mgmt__search_session_transcripts
---

# /onboard — Yeni Session Orientation

Yeni session açıldığında veya `/clear` sonrası, **minimum token ile** durumu topla VE handoff'taki Next Task Brief'i sun. Kullanıcı "evet" derse çalışmaya başla.

## Akış (6 adım)

### 0. RESUME DETECTION (KRİTİK — önce bu!)

Eğer bu fresh bir session DEĞİL de RESUME ise (transcript zaten büyük), kullanıcıya
**hemen uyarı ver ve dur**. Resume = cache_creation tax = pahalı.

```bash
# En son aktif transcript'in boyutunu bul
TRANSCRIPT=$(ls -t ~/.claude/projects/*/[0-9a-f]*.jsonl 2>/dev/null | head -1)
if [ -n "$TRANSCRIPT" ]; then
  SIZE_KB=$(($(stat -c '%s' "$TRANSCRIPT" 2>/dev/null || stat -f '%z' "$TRANSCRIPT") / 1024))
  if [ $SIZE_KB -gt 500 ]; then
    echo "🚨 RESUME ALGILANDI: Transcript $SIZE_KB KB"
    echo "   Eğer bu fresh session DEĞİLSE, devam etmek pahalı (cache_creation tax)."
    echo "   Öneri: /session-end → /clear → yeni session aç → /onboard"
  fi
fi
```

Eğer transcript > 500 KB ise:
- Stop ve kullanıcıya sor: "Bu session resume mu (eski) yoksa fresh mi (yeni)?"
- Resume ise: `/session-end` + `/clear` öner
- Fresh ise: devam et (Adım 1'e geç)

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
- `tasks/handoff.md` — single source of truth (Next Task Brief bölümü ile)
- `~/.claude/plans/<proj>-next-session-starter.md` — fallback (eski mekanizma, /session-end overwrite eder)
