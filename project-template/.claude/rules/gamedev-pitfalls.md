<!-- profile: gamedev -->
# Gamedev Pitfalls

> Distilled from `playbooks/gamedev-eng.md`. Game-specific domain pitfalls — additive to core rules.

## Save data & determinism

- Save format: every save struct is **versioned** (`SaveFile { version: u32, ... }`). Breaking change → migration code; never delete old saves unconverted.
- RNG: no global `random.seed()` / `Math.random()` — dedicated streams (`combat_rng`, `loot_rng`, `mapgen_rng`, `ai_rng`), each seeded separately. `grep Math.random` must be empty.
- Enums serialized for save/network are stable-IDed and append-only (`Sword=1, Bow=2, ... Axe=4`); never reorder or renumber.
- Multiplayer: deterministic sim required — float precision, iteration order, map/dict ordering must match across clients; decide & document upfront.

## Decisions & performance

- Balance changes (item stats, drop rates, XP curves, enemy HP) go to `tasks/decisions.md` with context/alternatives/outcome.
- ECS vs OOP: decide upfront, write to `decisions.md` before code — hard to reverse later.
- Frame budget (60fps=16.6ms / 30fps=33.3ms) is a hard constraint per system (update/physics/render/audio); profile after major changes, bisect regressions.

## Asset pipeline

- Raw assets (`.psd .blend .wav .fbx .fla .aep`) never enter git — only build outputs (`.png .ogg .glb`). Raw assets live in external storage / LFS.

## Pre-Commit Gate triggers (add to Tier 2)

```
save_format|save_version|serialize.*Save   → migration written?
random\.|Math\.random|rand\(\)             → dedicated RNG stream?
damage|stat|drop_rate|balance|xp_curve     → written to decisions.md?
enum.*=\s*\d+                              → stable ID, reorder-safe?
HashMap|dict\(\)|unordered_                → needs to be deterministic?
```

## Simplicity exceptions (allowed)

- ECS (100+ entities), observer/event bus, state-machine over conditional chains, object pooling for high-frequency spawns, versioned save serializer, dedicated RNG wrapper.

## Surgical-change exceptions

- Frame-budget violations and global-RNG leaks you spot: fix immediately, even if unrelated to the task.
