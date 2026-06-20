---
name: ask-local
description: Route appropriate work to local Ollama instead of Claude to save tokens. Use for single-shot summarization, classification, extraction, translation, or OCR. Never for code generation, multi-step reasoning, or anything requiring tool use.
allowed-tools: Bash, Read, Write
---

# /ask-local — Route work to local Ollama (Gemma 4 e4b primary · Qwen3.5 fallback)

Local Ollama is wired in as a tool. The models are good at **short, single-shot
tasks** and free to run. Claude's tokens are expensive. This skill is the routing
decision-maker: it picks the right model for each job, calls the Ollama wrapper, and
brings the result back to Claude.

**Default rung = `gemma4-fast-e4b`** (Gemma 4 E4B, QAT 4-bit). Benchmarked 2026-06-15
against the old `qwen35-fast-4b` default: equal/better quality, same speed class, runs
**100% GPU at ~3 GB** (Per-Layer Embeddings offload), and — unlike qwen — emits **clean
JSON without markdown fences**. `qwen35-fast-4b` stays wired as the fallback. The
`gemma4-fast-12b` rung was tested and **rejected**: it spills ~29% to CPU on the 8 GB
card (~2× slower) with no quality gain on these intents.

## When to use Ollama — the routing gate

**Route by how cheaply a wrong answer is caught, NOT by whether the model can sometimes
be right.** If wrongness is caught by a schema check / compile / test / grep / ~5-second
glance → routable. If catching a wrong answer costs as much reasoning as the task itself
→ keep it in Claude (RED, below). E4B (temp 0.3, clean fence-free JSON) is genuinely good
at *short, well-specified* tasks — it overlaps Claude only at the **floor** of bounded
work. That overlap is exactly this list; it is **not** Sonnet-class for reasoning/code
(it's right ~85–95% and confidently wrong on the tail, with no signal which).

### 🟢 GREEN — authoritative, route freely (mostly T0, no review)

Output is mechanically verifiable (schema/regex/grep) or a low-stakes digest. Model
`gemma4-fast-e4b`.

| Intent | Examples | Tier | Verify by |
|---|---|---|---|
| Summarize | log/output/stacktrace gist · git log/diff digest · PR/commit-range recap | T1 | glance |
| Classify (fixed labels → JSON) | commit type · log severity · language detect (TR/EN) · review sentiment · scraper status (ok/blocked/empty) | **T0** | label ∈ set |
| Extract (→ JSON schema) | TODOs/FIXMEs · URLs · dates · key-values from config/env-sample · symbol names from a file header · numbers from text (strip `$…$`) | **T0** | schema/regex |
| Transform / reformat (bounded) | list→md table · CSV↔JSON · JSON↔YAML · date-normalize · case-convert identifiers · list→checklist | **T0** | re-parse |
| Translate short (e4b primary now) | TR↔EN UI string · error message · doc paragraph <1K tok | T1 | glance |
| Pre-flight context trim | per-file digest → aggregate → feed Claude the digest (highest-leverage) | T1 | glance |

### 🟡 YELLOW — advisory draft / pre-filter ONLY (Claude or human finalizes, never authoritative)

E4B *can* do these, but the tail bites — output is a **starting point**, never
shipped/committed unreviewed. Treat as double-stitch advisory.

| Intent | Examples | Finalizer |
|---|---|---|
| Draft generation | commit-msg from a diff summary · changelog line · docstring stub · PR skeleton · test-name list | Claude edits |
| Bulk triage / pre-filter (~80%) | file-relevance for a task · dead-code candidate flagging · "which file likely has X" · near-dup detection · rank list by stated criterion | Claude decides |
| Soft reason-extraction | "lowest price in this list + why" · "most severe of these errors" · best-fit category from a fixed taxonomy | re-check the pick |
| First-pass review notes | flag obvious style/lint smells in a snippet · spot likely typos | Claude confirms |

> **9b fallback (`qwen35-fast`):** long technical translation (> 1K tok) + vision / image
> OCR. Keep input < ~4K tok (see VRAM note). e4b is multimodal too, but 9b is the vetted
> vision path.

> **VRAM ceiling (RTX 4070 Laptop, 8 GB).** Measured 2026-06-15 with flash attention +
> q8_0 KV cache on:
> - `gemma4-fast-e4b` (default) = **~3.0 GB resident, 100% GPU** at num_ctx 8192. E4B's
>   effective-param design offloads Per-Layer Embeddings to RAM, so it's lighter than
>   its 6.1 GB disk size. Comfortable — lots of headroom.
> - `qwen35-fast` (9b, fallback for long/vision) = 6.6 GB, ~1.4 GB left for KV; above
>   ~4K input tokens it spills to CPU and stalls (8K-token job = **46s** vs e4b's ~5s).
> - `gemma4-fast-12b` = **rejected** — 8.3 GB, spills 29% to CPU, ~2× slower, no quality
>   gain. Do not route here.
>
> **Server levers (required, set once):** `OLLAMA_FLASH_ATTENTION=1` +
> `OLLAMA_KV_CACHE_TYPE=q8_0` (Windows: `setx` then quit/relaunch Ollama from tray).
> Without these, Gemma defaults to 128K ctx + f16 KV and balloons. The
> `gemma4-fast-*` Modelfiles (in `scripts/modelfiles/`) bake `num_ctx` + Gemma sampling
> and keep Gemma's native chat template (no `{{ .Prompt }}` override).
## 🔴 RED — never local, always Claude (the line does NOT move)

The probes (2026-06-15: multi-step price math + code-bug spot, both passed) make this
*more* important, not less: E4B is **plausible-wrong**, and these are where wrongness is
expensive or invisible to catch.

- **Code** generation / refactor — anything that must compile or integrate
- **Multi-step *unverifiable* reasoning** · planning · debugging · architecture decisions
- Anything requiring **tool use** (edits, bash, multi-file search)
- **High blast-radius / data-integrity** — any *authoritative* decision where a wrong
  answer is costly or hard to reverse: security review · auth · DB migrations · schema /
  data changes · legal / compliance / policy · money or pricing calls · record-matching
  / dedup decisions. (Project-specific examples: record-matching decisions, money/pricing calls, your policy doc.) A YELLOW *suggestion* toward one of
  these is fine; the *authoritative* decision is always RED.
- Anything where a **confident-wrong answer silently corrupts downstream**
- Anything under ~50 tokens — overhead is bigger than the save

## How to call

From Claude Code (Bash tool), use the wrapper. Two surfaces:

### CMD (Windows native)
```cmd
scripts\ask-local.bat -Intent "summarize git log" -Prompt "<the log text>"
```

### PowerShell
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ask-local.ps1 `
  -Intent "summarize git log" -Prompt "<the log text>"
```

### Required parameters
- `-Intent` — short free-text purpose, used for logging and audit. Always set this.
- `-Prompt` — the actual text to send to Ollama.

### Optional parameters
- `-Model <name>` — default `gemma4-fast-e4b`. Use `qwen35-fast-4b` (fallback) or
  `qwen35-fast` (9b, long/vision).
- `-Tier <T0|T1|T2>` — default `T1`. T0 = no review needed (trivial). T1 = volume work. T2 = important enough to review (rare for Ollama).
- `-NoCache` — bypass disk cache; force fresh call.
- `-NoLog` — do not write call to log (privacy-sensitive inputs).

## Output contract

Every call returns a structured summary block followed by the response:

```
---OLLAMA-CALL-SUMMARY---
tier=T1 | intent=summarize git log | model=gemma4-fast-e4b | cached=false | ~840->210 tok | 1.4s
---OLLAMA-OUTPUT---
<the response text>
```

When you read this output, **always read the summary line first** — it tells you
which model ran, whether the response was cached, and roughly how many tokens were
spent locally (no Anthropic cost).

## Decision rules (binding)

1. **Always set `-Intent` with a clear short purpose.** Empty or vague intents
   defeat the audit log.
2. **Always pick the smallest viable model.** `gemma4-fast-e4b` first (100% GPU,
   default); `qwen35-fast` (9b) only for long/vision and only when input < ~4K tok.
   Never default to 9b, and never route to `gemma4-fast-12b` (CPU-spill, ~2× slower,
   no quality gain — see VRAM note).
3. **Prefer templates over ad-hoc prompts.** See `templates/local-prompts/` for
   well-tuned prompt skeletons. They produce more reliable output than free-form.
4. **Route by verifiability, not by topic** (see the routing gate + zones). Code
   *generation / refactor / authoritative decisions* are RED → Claude. But reading
   code-as-text for a **bounded, verifiable** result is fine: extracting symbol names
   or classifying a commit *message* is GREEN; drafting a commit-msg from a diff summary
   or flagging style smells is YELLOW (advisory — Claude finalizes). Never route an
   authoritative code or data-integrity decision locally.
5. **If the same intent fires 10+ times in a session,** suggest promoting it
   to a dedicated mini-skill or a saved template.
6. **Cache hits do not produce new tokens locally.** Treat them as free, but
   still log them — they prove the optimization is working.

## Common patterns

### Pre-flight context trim (highest-leverage pattern)
Before sending a large blob to Claude, summarize each piece in Ollama, then send
Claude the digest. Example flow:

```
For each file in tasks/refs/*.md:
  ask-local -Intent "summarize ref file" -Prompt "<file contents>"
  → append response to digest.md
Send digest.md to Claude instead of all originals.
```

Typical saving: 60-80% of input tokens for that step.

### Classify into JSON
```
ask-local -Intent "classify commit type" `
  -Prompt "Classify this commit message into one of [feat,fix,refactor,docs,test,chore]. Respond as JSON: {""type"": ""<label>"", ""confidence"": <0-1>}. Message: fix auth retry loop"
```

### Translate
```
ask-local -Intent "translate TR->EN" `
  -Prompt "Translate to English. Preserve technical terms. Text: ..."
```

## Failure modes to watch

- **Output longer than expected.** If Ollama returns >2x expected length, treat
  as suspicious; the prompt likely lacked length constraint.
- **Format drift in JSON.** Smaller models occasionally emit markdown code fences
  around JSON. Strip them before parsing.
- **Repeated cache hits with stale answer.** If you suspect cache is wrong,
  re-call with `-NoCache`.
- **Ollama service down.** Exit code 2. Fall back to Claude for the task; flag
  in handoff that Ollama was unavailable.

## Related

- `scripts/ask-local.ps1` — primary worker script
- `scripts/ask-local.bat` — CMD wrapper
- `templates/local-prompts/` — vetted prompt templates per intent
- `.ollama-log/<session>/calls.jsonl` — per-session audit trail
