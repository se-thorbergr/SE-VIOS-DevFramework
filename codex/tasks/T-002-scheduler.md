# Task T-002 — Coroutine Scheduler & Budgets

**Mode:** CODE-SKELETON (incremental) • **Targets:** MDK²-SE, C# 6, netframework48

## Goal

Add a cooperative coroutine scheduler that slices work across ticks and enforces TIC and call‑depth budgets.

## Scope

- Types: `CoroutineId` (struct), `ICoroutine` (interface), `Coroutine` (class), `CoroutineScheduler` (class).
- Budget config: Soft/Hard TIC limits (default 30000/45000), MaxDepth (50), read from `CustomData`.
- Yield tokens: `Yield.Now`, `Yield.NextTick`, `Yield.After(int ticks)`. No `async/await`.
- Integration: `VIOSKernel.Tick()` pumps `CoroutineScheduler` before/after module ticks; scheduler returns whether to continue or yield.

## Constraints

- No allocations per frame once running (pre-size lists/queues).
- Use `Runtime.CurrentInstructionCount` and `Runtime.CurrentCallChainDepth`.
- Expose stats (queued coroutines, ran this tick, yields) for LCD.

## Deliverables

- `Mixins/VIOS.Core/Scheduler.cs` with scheduler + simple `Coroutine` implementation.
- Hooks in `VIOSKernel` to schedule module work (e.g., discovery scans) via scheduler.
- Minimal unit‑style demonstration inside `Tick()` (e.g., a coroutine that counts to N across ticks) guarded by `#if DEBUG` if needed.

## Acceptance Criteria

- Scheduler stops executing when Soft TIC reached and yields; never crosses Hard TIC.
- MaxDepth respected; if exceeded, scheduler defers remaining work.
- No GC allocations in the steady state (inspect with counters/heap alloc logs if available).
- Passes `tools/check-architecture.ps1`.

## References

- `docs/architecture/VIOS-Architecture.md` (Scheduler section)
