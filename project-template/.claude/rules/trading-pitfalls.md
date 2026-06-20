<!-- profile: trading -->
# Trading Bot Pitfalls

> Distilled from `playbooks/trading-bot-eng.md`. Trading-specific domain pitfalls — additive to core rules.

## Money & data integrity

- Money is always `Decimal`, never float (`from decimal import Decimal`) — price, quantity, balance, PnL.
- `except: pass` / `except: continue` is forbidden — silent fail = money loss (wrong position, missed trade, stale data). Fail loud: log + alert + kill switch.
- Timestamps are UTC everywhere (`datetime.now(timezone.utc)`), convert to local only at display. No bare `datetime.now()` / `utcnow()`.
- Order idempotency: every order gets a `client_order_id` (UUID); exchange's idempotent API rejects duplicates.

## Rate limits & validation

- Every exchange API call goes through a rate limiter with burst handling + exponential backoff — `time.sleep(1)` alone is not enough.
- Backtest ≠ live: mandatory chain is Backtest → Paper trading (3-7 days) → Small live → Full live. Don't skip links.

## Decisions

- Position sizing, leverage, and max-drawdown limits go to `tasks/decisions.md` — reversible-consequence decisions need a documented "why".

## Pre-Commit Gate triggers (add to Tier 2)

```
float.*(price|amount|balance|pnl|qty)     → should use Decimal
time\.sleep\(.{1,5}\)                      → rate limiter present?
except.*:\s*pass|except.*:\s*continue      → silent fail
datetime\.now\(\)|utcnow\(\)               → tz-aware (.utc)?
position|order|trade.*submit              → idempotency key present?
leverage|max_drawdown|risk                → written to decisions.md?
```

## Simplicity exceptions (allowed)

- Verbose logging (trade history reconstruction), externalized config (API keys/strategy params/risk limits), dead-man's-switch heartbeat + auto-kill.

## Surgical-change exceptions

- Deterministic event replay (state+input logging) for bug repro counts as a safety layer, not scope creep.
