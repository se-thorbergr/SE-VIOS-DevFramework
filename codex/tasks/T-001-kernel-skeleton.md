# Task T-001 — Implement VIOSKernel & Env Skeletons

**Mode:** CODE-SKELETON • **Targets:** MDK²-SE, C# 6, netframework48 • **Project types:**

- PB script: `Scripts/VIOS.Bootstrap` (mdk2pbscript)
- Core mixin: `Mixins/VIOS.Core` (mdk2mixin)

## Goal

Create a branded `VIOSKernel` plus minimal `Env`/config adapters and PB bootstrap wiring so the script builds and ticks without logic errors.

## Scope

- Interfaces: `IVIOSKernel`, `IVIOSModule`, `IModuleRegistrar`, `IEnv`, `IConfig` (branded where appropriate).
- Concrete: `VIOSKernel`, `Env`, `IniConfig` minimal implementations.
- PB wiring: `Program()` constructs Env/Config/Kernel, registers two neutral sample modules (`PowerModule`, `ScreenManagerModule`), sets UpdateFrequency (`Update10|Update100`).
- Error surfacing: one `try/catch` in `Main()`; echo concise error line and optional debug LCD message.

## Constraints (must obey)

- All executable code within `namespace IngameScript { partial class Program { ... } }`.
- **C# 6 only / .NET 4.8.** Prefer **VRage** APIs.
- **Branding:** type names containing OS use uppercase **VIOS**; variables may be `vios` lowercase. Modules keep **neutral** class names.
- No allocations in hot `Tick()` paths; plan for pooling but implement minimal no-GC loops now.

## Deliverables

- `Mixins/VIOS.Core/VIOS.cs`: interfaces + `VIOSKernel` skeleton.
- `Mixins/VIOS.Core/Env.cs`: `Env` adapter exposing `Me`, `Runtime`, `GTS`, `IGC`, `Echo`, UtcNow, Debug surfaces.
- `Mixins/VIOS.Core/Storage.cs`: `IniConfig` reading `Me.CustomData` with `MyIni`.
- `Scripts/VIOS.Bootstrap/Program.cs`: PB driver wiring kernel & modules.

## Acceptance Criteria

- Builds Release via MSBuild on Windows.
- PB starts with `Update10|Update100`, does not throw.
- Echo shows a one‑line status (e.g., `VIOS: running` + tick info).
- Code passes `tools/check-architecture.ps1` & pre-commit header checks.

## References

- `docs/architecture/VIOS-Architecture.md`
- `docs/prompts/VIOS-Prompt-Reusable.md`
- `AGENTS.md`
