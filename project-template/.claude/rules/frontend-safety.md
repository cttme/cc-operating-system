<!-- profile: web -->
# Frontend Safety Rules

- JSON-LD icin ASLA `JSON.stringify` kullanma — her zaman `safeJsonLd()` (lib/utils.ts)
- `dangerouslySetInnerHTML` kullanmadan once: icerigi sanitize et veya escape et
- Kullanici girdisi (yorum, isim) `bleach.clean()` ile backend'de temizlenmeli
- API fetch catch bloklari: `.catch(() => {})` YASAK — en azindan console.error logla
- localStorage tercihleri backend davranisini degistirmez — server-side preference gerekiyorsa API endpoint yaz
- Auth token sadece localStorage'da, URL parametrelerine ASLA koyma
- Modal/dialog checklist: dialog + aria-modal + aria-labelledby + Escape + scroll lock + Tab trap + focus return
