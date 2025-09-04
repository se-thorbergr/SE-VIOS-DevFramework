# Task T-004 — Wire ScreenMgr & Power modules end-to-end

**Mode:** MODULE • **Targets:** MDK²-SE, C# 6, netframework48 • **Project:** mdk2mixin modules

## Goal

Finish the neutral `ScreenManagerModule` and `PowerModule` and integrate with kernel/router/scheduler.

## Scope

- `ScreenManagerModule`:
- Discover configured surfaces from `CustomData` (ALCD2-compatible hints ok).
- Draw header (`VIOS` + ship/station name) and UTC timestamp; small footer with TIC.
- Cadence configurable: `[ScreenMgr] Draw.Cadence=Update10` (default Update10).
- `PowerModule`:
- Aggregate stored/max/IO for batteries/reactors/solars/H2 engines.
- Expose `DescribeStatus(StringBuilder)` and respond to `Power.Status?` messages with a compact line.
- Hook modules to scheduler for non-trivial discovery (slice across ticks for large grids).

## Constraints

- Neutral class names; implement `IVIOSModule`.
- No allocations in `Tick()`; reuse lists and `StringBuilder`.
- Respect TIC and call‑depth budgets before long scans.

## Deliverables

- `Mixins/Modules/ScreenMgr/ScreenManagerModule.cs` (finalized)
- `Mixins/Modules/Power/PowerModule.cs` (finalized)
- CustomData examples in PR description.

## Acceptance Criteria

- LCD shows header + UTC + footer; no flicker; respects cadence.
- Power stats update; message `Power.Status?` yields a reply packet.
- No new allocations in steady state; passes architecture checks; Release builds.

## References

- `docs/architecture/VIOS-Architecture.md` (UI & Modules)
