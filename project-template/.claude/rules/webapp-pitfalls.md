<!-- profile: web -->
# Webapp Pitfalls

> Distilled from `playbooks/webapp-eng.md`. Web-specific domain pitfalls — additive to core rules.

## Security

- XSS: raw HTML via `innerHTML=`, `dangerouslySetInnerHTML`, `v-html`, `{@html}` — sanitize with DOMPurify, no exceptions.
- CSRF: writes (POST/PUT/DELETE/PATCH) need CSRF tokens or `SameSite=Strict` + framework middleware.
- SQL injection: no string-interpolated queries — ORM or parameterized (`?`/bind params) only.
- Hardcoded env vars (`API_URL = "http://localhost:3000"`): dev-green/prod-red trap — always `process.env.X` / `os.environ["X"]`, commit `.env.example`.
- Production log leak: `console.log`/`print(user)` of user data — strip in build (drop_console/terser), mask PII server-side.

## Performance

- N+1 queries: `items.forEach(i => db.related.where({itemId: i.id}))` — use ORM `include`/`join`, verify with `EXPLAIN`.

## Accessibility & SEO minimum bar

- Every `<img>` has `alt` (`alt=""` if decorative); `<button>`/`<a>`, never `<div onclick>`; logical Tab order + focus trap; AA contrast (4.5:1).
- Unique `<title>` + `<meta description>` per page; exactly one `<h1>`; OG tags; `sitemap.xml` + `robots.txt`.

## Pre-Commit Gate triggers (add to Tier 2)

```
innerHTML\s*=|dangerouslySetInnerHTML|v-html|\{@html\}  → XSS, sanitized?
eval\(|new Function\(                                    → code injection
SELECT.*\$\{|f".*SELECT|SELECT.*%s.*%                    → SQL injection
http://localhost|127\.0\.0\.1                            → move to env var
console\.log|console\.debug|print\(                      → production leak
```

## Simplicity exceptions (allowed)

- Error boundary, form-validation schema (Zod/Yup), centralized API client wrapper — not over-engineering here.

## Surgical-change exceptions

- A11y fixes and security patches: flag AND fix even if "unrelated" to the task.
