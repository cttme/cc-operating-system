---
name: bootstrap-project
description: Yeni bir Claude Code projesini sıfırdan kur — template kopyala, placeholder doldur, hook/skill altyapısı, git init
allowed-tools: Bash, Read, Write
---

# /bootstrap-project — Yeni Proje Kurulumu

Sıfırdan bir proje başlatırken bu chat'in inşa ettiği token-optim + düzen koruma sisteminin tamamını kurar.

## Akış

### 1. Bilgi Topla

Kullanıcıya sor:
```
Yeni proje için bilgi:
1. Proje adı?
2. Klasör yolu? (boş = mevcut dizin)
3. Kısa açıklama (1 cümle)?
4. Tech stack? (örn: "Python 3.13 + FastAPI", "Next.js 14", "Go + Postgres")
5. Frontend port? (default 3000)
6. Backend port? (default 8000)
7. Dev deps şimdi yüklensin mi? (evet/hayır)
8. Git init yapılsın mı? (evet/hayır)
```

### 2. Script Çağır

Topla cevapları ve çalıştır:

```bash
python ~/.claude/scripts/new-project.py "<TARGET_PATH>" \
  --name "<NAME>" \
  --description "<DESC>" \
  --tech "<TECH>" \
  --frontend-port <FE_PORT> \
  --backend-port <BE_PORT> \
  --profile <core|web|scraper|library> \
  [--install-deps] [--skip-git]
```

`--profile` seeds only the matching `.claude/rules/` tier (default `core`; non-core
profiles are additive over core). Pick `web` for a frontend, `scraper` for a data
collector, `library` for minimal. "Sharp ≠ heavy" — a web project shouldn't ship
buried under scraper rules.

### 3. Script Çıktısını Göster

Script şunları yapacak:
- `~/.claude/templates/project-bootstrap/` template'inden tüm dosyaları kopyalar
- Placeholder'ları doldurur (`{{PROJECT_NAME}}` vb.)
- `.template` uzantılarını kaldırır
- Git init + initial commit (opsiyonel)
- Dev deps yükleme talimatı (opsiyonel)

### 4. Sonraki Adımları Söyle

```
✓ Bootstrap tamamlandı.

Sıradaki:
  cd <target>
  pip install -r requirements-dev.txt
  pre-commit install
  
  # Claude Code'da yeni session aç, ÖNCE constitution kur:
  /kickoff    # project-zero interview → docs/CONSTITUTION.md + decision #0
              # (thesis → CLAUDE.md identity line; DoD → session-end checks it)
  /onboard
```

> `/kickoff` replaces the old "manually edit CLAUDE.md / fill PRODUCT.md" step — it
> front-loads the one-way-door decisions (thesis, architecture, DoD, risks, tiers)
> into a one-page constitution instead of leaving them to accrete ad-hoc.

## Ne Kurar?

Bootstrap edilen yapı:

```
<proje>/
├── CLAUDE.md                  ← Slim, lookup table
├── .claudeignore              ← Aggressive ignore
├── .gitignore                 ← bak-* eklemeleri
├── .pre-commit-config.yaml    ← 7 hook seti
├── pyproject.toml             ← ruff/mypy/bandit/coverage
├── requirements-dev.txt       ← dev deps
├── .claude/
│   ├── settings.json          ← 4 kategori hook
│   └── rules/
│       └── change-protocol.md ← Yüksek-risk disiplini
├── scripts/                   ← 4 hook script
│   ├── size_guard.py
│   ├── check_config_syntax.py
│   ├── check_claude_refs.py
│   └── session_budget_check.py
├── tasks/                     ← Claude memory
│   ├── handoff.md (boş, standart format)
│   ├── todo.md
│   ├── lessons.md
│   ├── decisions.md
│   ├── audit.md
│   ├── precheck-stats.md
│   ├── refs/README.md
│   └── archive/
└── docs/                      ← Modüler docs
    ├── PRODUCT.md (template)
    └── ARCHITECTURE.md (template)
```

## Ne Otomatik Değil?

Bootstrap sonrası **manuel** yapılacaklar:

1. **External tools** (sistem genelinde, bir kere):
   ```bash
   npm install -g ccusage ccstatusline context-mode repomix
   pip install ruff mypy bandit pre-commit vulture pytest-cov
   ```
2. **Pre-commit install** (proje içinde):
   ```bash
   cd <proje>
   pre-commit install
   ```
3. **CLAUDE.md'yi projeye özelleştir** (boilerplate var, sen detaylandır)
4. **Modül `index.md`'leri yaz** (her ana klasör için, ihtiyaç oldukça)
5. **`docs/PRODUCT.md` ve `docs/ARCHITECTURE.md` doldur**

## Kullanım

```
/bootstrap-project
```

Skill sana soruları sorar, sonra script'i çalıştırır.

## Ek

İlk yeni session'da projeye girince:
```
/onboard
```
Skill handoff.md'yi okur. Boş ise: "Bu yeni proje, ne yapmak istersin?" sorar.
