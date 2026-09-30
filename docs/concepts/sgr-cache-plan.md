# Style Caching as Pre-Computed SGR Strings

Status: Proposed. This plan addresses style resolution performance using data from profiler runs (2026-09-30, commit 8274c7f with local modifications, `--deep` mode).

## 1. Performance Analysis

Profiling indicates that the Style layer accounts for 21% of cumulative interaction time. Two functions repeatedly resolve identical styles and represent the primary bottleneck:

| function | calls per pass of all scenarios | self time | per call |
|---|---|---|---|
| `_tui._sgr_from` (lib/tui.sh:1455) | ~2,850 | ~220 ms | 78 µs |
| `_tui._style_v` (lib/tui.sh:1481) | ~1,040 | ~58 ms | 56 µs |
| `_tui.theme_parse` (lib/style/tui_style.sh:67) | 300 | ~46 ms | 150 µs |

Profiled execution shows Style layer cost at approximately 70 ms of a 340 ms page switch, 40 ms of a 150 ms resize, and 43 ms of a 140 ms palette dismissal. Each page typically employs only several dozen distinct styles; consequently, nearly every resolution invocation recomputes a string identical to an earlier computation within the same frame.

Current behavior: `_tui._style_v` performs up to six associative reads and three string tests, then invokes `_tui._sgr_from`, which parses hex values via three base-16 conversions per color, resolves named colors, iterates modifiers, and concatenates escape sequences. All operations are deterministic; output depends solely on the three input strings (foreground, background, modifiers).

## 2. Design Approach

The caching strategy employs two layers. Each provides independent benefit; the second layer eliminates the computational cost of the first from the critical rendering path.

### 2a. Function-Level Memoization (Conservative, Low Risk)

```
declare -gA _TUI_SGR_MEMO=()     # "fg|bg|mods" -> SGR string ("" is a valid value)
```

Modify `_tui._sgr_from` to check the memoization table before computation:
1. Construct key `k="$1|$2|$3"`; if `${_TUI_SGR_MEMO[$k]+x}` is set, assign `_SGR=${_TUI_SGR_MEMO[$k]}` and return.
2. Otherwise compute as currently implemented and cache the result only on success. Failures (unrecognized color names returning 1) remain uncached to preserve fallback path behavior.

The pipe character serves as key separator; it cannot appear in color hex values, named colors, or space-separated modifier lists. Use `${var+x}` test syntax rather than `-n` to distinguish cached empty strings from absent keys.

Expected performance improvement: `_sgr_from` latency reduces from approximately 78 µs to 3 µs on cache hits (single associative lookup plus assignment). The cache requires no explicit invalidation, as identical inputs always produce identical output.

### 2b. Per-Style-Key Caching (Eliminates Fallback Resolution)

The function `_tui._style_v KEY FB BGFB` performs up to six associative lookups and three string comparisons before invoking `_sgr_from`. Cache the resolved result once per unique parameter triple:

```
declare -gA _TUI_STYLE_SGR=()    # "key|fb|bgfb" -> SGR string
```

Implementation:
1. Compute key `k="$1|${2:-}|${3:-}"`; on cache hit, assign `_SGR=${_TUI_STYLE_SGR[$k]}` and return.
2. On cache miss, resolve using the current implementation, store the result, and return.

This table also serves `_tui.emit_ring` (with key pattern `"ring|$key|$fb|$id"` to prevent collisions between ring and style entries, given different ring background fallback semantics) and direct `_sgr_from` invocations at lib/widgets/tui_widgets.sh:430 and lib/tui_api.sh:789.

The naming prefix `_TUI_STYLE_` is intentional: `_TUI_CACHE_STATE_REGEX` (lib/markup/tui_cache.sh:56) includes this prefix, enabling automatic serialization and deserialization within page snapshots alongside other style state. Verification requirement for initial rollout: ensure snapshot keys include the active theme overlay to prevent restored SGR tables from persisting across theme changes.

### 2c. Optional: Eager Baking at Style Definition

Only two functions write to `_TUI_STYLE_*`: `tui.style` (lib/style/tui_style.sh:32) and `_tui_cache_class` (lib/markup/tui_cache.sh:198). Eager computation at these write points for the no-fallback triple `key||` moves first-access misses to initialization time and allows page caches to carry pre-warmed SGR strings, eliminating style overhead on warm page loads. Implement this phase only if profiling after 2a and 2b reveals first-frame style cost; lazy population suffices for repeated rendering passes.

## 3. Cache Invalidation Strategy

| event | what changes | action |
|---|---|---|
| any change to a style triple (`tui.style`, `_tui_cache_class`, class application) | one or more `_TUI_STYLE_*[key]` | clear `_TUI_STYLE_SGR` (whole table, it refills in one frame); `_TUI_SGR_MEMO` untouched |
| theme change (`tui.theme.set/clear/reload`, `tui.load_theme`) | `_TUI_CLASS_*`, then every baked style | clear `_TUI_STYLE_SGR` |
| page reset (`tui.reset_ui`, lib/markup/tui_markup.sh:217 sets `_TUI_STYLE_FG=()`) | style tables emptied | clear `_TUI_STYLE_SGR` in the same function |
| hover/focus/checked state change | none: state is part of the key (`id_hover`, `id_focus`) | nothing |
| colour-depth or palette change, if ever added | SGR encoding itself | clear both tables |

Invalidation rule: any code path that writes to `_TUI_STYLE_{FG,BG,MOD}` must invalidate `_TUI_STYLE_SGR`. A dedicated helper function `_tui_style.touch` implements this via `_TUI_STYLE_SGR=()`, invoked from all three write locations. Stale baked strings constitute a correctness failure; all write paths must perform invalidation.

Granular invalidation (per-key deletion) adds unnecessary complexity: style application writes multiple keys in a single operation, and the cache repopulates within one frame via lazy fill.

## 4. Implementation Phases (Test-Driven per DABT Standards)

1. **Baseline Profiling**: Execute `tools/profiler/profile.sh --deep` and retain results. Record call counts and self-time for `_sgr_from` and `_style_v`, Style layer overhead per scenario, and baseline measurements from `tools/bench/run.sh` for `full_render`, `hover_redraw`, and `focus_move`.

2. **Unit Tests** (tests/unit, host-independent, isolated):
   - Verify `_sgr_from` cache hits produce byte-identical output to uncached calls across hex colors, named colors, modifiers-only, empty styles, and mixed inputs.
   - Confirm unrecognized color names return error code 1 and remain uncached; subsequent calls still return 1.
   - Verify `_style_v` returns identical `_SGR` values before and after cache population, with and without `fb`/`bgfb` parameters.
   - Confirm that `tui.style` modifications cause `_style_v` to return updated strings (invalidation verification).
   - Verify that `tui.theme.set` invalidation eliminates cached strings.
   - Confirm `_tui.emit_ring` and `_style_v` with equivalent inputs maintain separate cache entries.

3. **Phase 2a Implementation**: Implement function-level memoization (section 2a), run tests, bench, and profiler. Expected outcome: Style layer reduction exceeding 50%.

4. **Phase 2b Implementation**: Add per-style-key caching and `_tui_style.touch` helper (section 2b), rerun tests, bench, and profile.

5. **Phase 2c Decision**: Evaluate profiling results to determine whether eager baking (section 2c) provides additional benefit.

6. **Cleanup**: Remove code superseded by caching. Preserve duplicated resolution logic in `_tui._apply_style` where it serves fallback paths only; make no speculative deletions.

7. **Documentation**: Add function headers per docstrings.md; instrument performance tracking with `_tui_perf.count sgr_hit` and `sgr_miss` inside `_style_v` (implemented as a single conditional test when tracking is disabled).

8. **Verification**: Run `tools/profiler/profile.sh --deep` and compare against baseline (automatic differential analysis).

## 5. Acceptance Criteria

- Combined self-time for `_tui._sgr_from` and `_tui._style_v` reduced to below 40 ms per profiler pass (from approximately 280 ms).
- Style layer overhead for page switch operations reduced to at most 15 ms (from approximately 70 ms), with page switch median latency reduced by approximately 50 ms.
- Output byte-identical across all demo pages and theme combinations, verified via `tools/debug/screenshots.py` or golden frame comparisons (tools/golden).
- No introduction of process forks on any execution path, verified via `tools/debug/count_forks.sh`.
- Memory footprint: both cache tables remain under several hundred entries per page; measure via `declare -p` size on the largest page.

## 6. Risk Mitigation

- **Stale cache entries from missed invalidation**: Mitigated by the centralized `touch` helper and comprehensive unit tests for invalidation paths (phase 4, step 2). Code review must grep for all writers of `_TUI_STYLE_*` to ensure exhaustive invalidation coverage.

- **Snapshot/theme desynchronization** (see section 2b): Verification during phase 1 baseline testing required. Fallback approach: exclude `_TUI_STYLE_SGR` from page snapshots and allow repopulation after load.

- **Key separator conflicts**: The pipe character separator is safe for current color and modifier syntax. If future color representations introduce pipe characters, migration to `$'\x1f'` (unit separator) as delimiter is straightforward.

- **Unbounded cache growth with dynamic styles**: Per-row generated colors (gradients, charts) create unlimited distinct cache keys. Implement size limits on memoization tables (e.g., clear when exceeding 4096 entries); the charts demonstration page serves as validation.

## 7. Scope Boundaries

The following optimizations fall outside this plan and are addressed by the cheap-redraw strategies in `cheap-redraws-concept.md`: transition strings between style states (emitting only changed attributes), color degradation across palette depths (256-color and 16-color fallbacks), and selective SGR emission based on prior-frame attribute matching.
