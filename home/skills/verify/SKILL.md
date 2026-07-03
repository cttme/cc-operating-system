---
name: verify
description: Çift kontrol bateryası — dosya bütünlüğü, syntax validation, referans linkleri, hooks, tools, yedekler. Risk-tabanlı sağlık kontrolü.
allowed-tools: Read, Bash, Glob, Grep
---

# /verify — Çift Kontrol Bateryası

Tek komutla **8 kontrol** çalıştır, PASS/WARN/FAIL özet ver. Yüksek-risk değişikliklerden sonra veya periyodik sağlık kontrolü için.

## Çalıştırma

`PYTHONIOENCODING=utf-8` ortamı ayarla (Windows cp1254 unicode hatasını engelle).

### Kontrol 1 — Dosya Bütünlüğü

Beklenen yapı dosyaları:
```bash
for f in CLAUDE.md POLICY.md docs/PRODUCT.md docs/ARCHITECTURE.md \
         pyproject.toml requirements-dev.txt .claudeignore .gitignore \
         .pre-commit-config.yaml .claude/settings.json \
         scripts/size_guard.py; do
  if [ -f "$f" ]; then printf "  OK %s\n" "$f"
  else printf "  MISSING %s\n" "$f"; fi
done
```

Module navigation:
```bash
for d in api feeds matcher db reviews services search utils scrapers; do
  if [ -f "$d/index.md" ]; then printf "  OK %s/index.md\n" "$d"
  else printf "  MISSING %s/index.md\n" "$d"; fi
done
```

### Kontrol 2 — Syntax Validation

```bash
PYTHONIOENCODING=utf-8 python -c "
import json, yaml, tomllib
ok = err = 0
for f in ['.claude/settings.json']:
    try:
        with open(f, encoding='utf-8') as fp: json.load(fp)
        print(f'  OK  {f}'); ok += 1
    except Exception as e:
        print(f'  ERR {f}: {e}'); err += 1
for f in ['.pre-commit-config.yaml']:
    try:
        with open(f, encoding='utf-8') as fp: yaml.safe_load(fp)
        print(f'  OK  {f}'); ok += 1
    except Exception as e:
        print(f'  ERR {f}: {e}'); err += 1
try:
    with open('pyproject.toml', 'rb') as fp: tomllib.load(fp)
    print('  OK  pyproject.toml'); ok += 1
except Exception as e:
    print(f'  ERR pyproject.toml: {e}'); err += 1
print(f'Syntax: {ok} OK, {err} ERR')
"
```

### Kontrol 3 — CLAUDE.md Referans Linkleri

```bash
PYTHONIOENCODING=utf-8 python -c "
import re, os, subprocess
text = open('CLAUDE.md', encoding='utf-8').read()
refs = set(re.findall(r'\`([\w/.-]+\.(?:md|py|json|yml|toml))\`', text))
ok = missing = 0
missing_list = []
for ref in refs:
    if os.path.exists(ref):
        ok += 1
    else:
        # Yanlış pozitif kontrolü: dosya başka yerde olabilir
        found = subprocess.run(['find', '.', '-name', os.path.basename(ref), '-not', '-path', '*/node_modules/*', '-not', '-path', '*/.next/*', '-not', '-path', '*/archive/*'], capture_output=True, text=True).stdout.strip()
        if found:
            ok += 1
        else:
            missing += 1
            missing_list.append(ref)
print(f'Refs: {ok} resolved, {missing} truly missing')
if missing_list:
    print('Missing (gerçek):')
    for m in missing_list: print(f'  - {m}')
"
```

### Kontrol 4 — size_guard (drift)

```bash
python scripts/size_guard.py 2>&1
```

### Kontrol 5 — Hooks Aktif mi + Hook Health

```bash
PYTHONIOENCODING=utf-8 python -c "
import json
s = json.load(open('.claude/settings.json', encoding='utf-8'))
h = s.get('hooks', {})
print(f'Hooks aktif: {len(h)} kategori → {list(h.keys())}')
expected = {'SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'Stop'}
missing = expected - set(h.keys())
if missing: print(f'  EKSIK: {missing}')
else: print('  Tum kategoriler mevcut')
"

# Hook-health: canned payload through each file-based hook script (O2, os-remap).
# Executes hooks for real — a dead/dying hook FAILs here, config presence alone
# does not prove liveness. Also reads+archives tasks/.trajectory_errors.log and
# prints calibration born-on dates. Project-local; skip silently if absent.
[ -f scripts/hook_health.py ] && PYTHONIOENCODING=utf-8 python scripts/hook_health.py
```

> Hook-health FAIL (exit 1) = GENEL STATUS **FAIL** — bir hook script çöktü demektir.
> WARN (error-log non-empty) = değerlendir; log tail'i incele, arşivlendi.

### Kontrol 6 — Pre-commit Config

```bash
pre-commit validate-config .pre-commit-config.yaml 2>&1
```

### Kontrol 7 — Tool Versiyon Drift

```bash
for cmd in "ccusage --version" "ruff --version" "mypy --version" "bandit --version" \
           "pre-commit --version" "vulture --version" "repomix --version" "rtk --version"; do
  result=$($cmd 2>&1 | head -1)
  printf "  %-15s %s\n" "$(echo $cmd | cut -d' ' -f1):" "$result"
done
```

### Kontrol 8 — Yedek Dosyalar (Rollback Hazır mı)

```bash
echo "Yedekler:"
ls -la *.bak-* 2>&1 | head -5
ls -d *.bak-*/ 2>&1 | head -3
```

## Final Çıktı Formatı

Sonunda **tek satırlık özet** ver:

```
═══════════════════════════════════════════════════
   /verify SONUCU
═══════════════════════════════════════════════════
  Dosya integrity:   X/Y OK
  Syntax:            X/Y PASS
  Referanslar:       X resolved, Y truly missing
  size_guard:        X warnings (sayı kabul edilebilir mi?)
  Hooks:             4/4 aktif
  Pre-commit:        VALID
  Tools:             X/8 kuruldu
  Yedekler:          MEVCUT / EKSİK
───────────────────────────────────────────────────
  GENEL STATUS: PASS | WARN | FAIL
═══════════════════════════════════════════════════
```

## Kurallar

- **Sadece rapor üret** — düzeltme yapma. Kullanıcı kararını ver.
- **Token-efficient:** Tüm çıktıları head/tail ile sınırla.
- **Hata yutma:** Bir kontrol başarısızsa neden açıkça yaz.
- **WARN ≠ FAIL:** size_guard uyarıları WARN; eksik dosya/syntax hatası FAIL.

## Kullanım Senaryoları

- **Yüksek-risk değişiklik sonrası:** CLAUDE.md edit, tasks/ restructure, hook değişikliği
- **Haftalık sağlık:** Pazar sabahı `/verify` çalıştır
- **Yeni session açıldığında:** `/onboard` + `/verify` ikilisi (önemli sapma var mı)
- **Before `/clear`:** Devir öncesi son sağlık kontrolu

İlgili: `.claude/rules/change-protocol.md` (yüksek-risk listesi).
