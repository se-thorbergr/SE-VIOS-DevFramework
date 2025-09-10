# AGENTS.md — VIOS Codex Guide

> Version: 2025-09-09 • Owner: **geho** • Project: **Viking Industries Operating System (VIOS)** for Space Engineers (MDK²-SE)
>
> This file tells coding agents (e.g., GitHub Copilot / Codeium / ChatGPT in VS Code) **how to work in this repo**: layout, rules, tasks, acceptance, and CI. Treat it as the single source of truth during implementation.

---

## 1) Mission & Scope

- Build an extensible _in-game OS_ for Space Engineers **Programmable Blocks**.
- Use **MDK²-SE** with **VS Code**; target **.NET Framework 4.8** and **C# 6**.
- **VRage-first** APIs. PB whitelist compliant. Avoid async/await, tuples, pattern matching, Span, or LINQ in hot paths.

**Branding**

- **VIOS** = OS product brand. **Type names** containing the OS must use uppercase **VIOS** (e.g., `VIOSKernel`, `IVIOSModule`).
- **Modules** and **Components** keep neutral names but implement branded interfaces.
- Variables/fields may use lowercase `vios` (e.g., `_viosKernel`).

---

## 2) Repository Layout & Project Types

### Canonical layout

```text
<root>/
├─ Scripts/                # mdk2pbscript (thin PB bootstraps)
│  ├─ VIOS.Bootstrap/      # reference PB for Workshop
│  │  ├─ Program.cs
│  │  └─ VIOS.Bootstrap.csproj
│  └─ <OtherPB>/...
├─ Mixins/                 # mdk2mixin (reusable source)
│  ├─ VIOS.Core/           # branded core types only
│  ├─ Components/          # neutral building blocks
│  └─ Modules/             # neutral feature modules
├─ ThirdParty/             # optional vendor mixins (git submodules)
├─ docs/                   # architecture, prompts, policies, steam
├─ codex/                  # task briefs + acceptance
├─ tools/                  # scaffolders, verifiers, stampers
├─ .github/                # CI, issue templates
├─ .githooks/              # pre-commit header stamper
└─ Directory.Build.props   # global LangVersion=6, netframework48
```

### Project types & wiring

- **PB scripts** (`mdk2pbscript`) live in `Scripts/`, include the MDK² packager.
- **Core**, **Modules**, **Components** are `mdk2mixin` projects in `Mixins/`. PB scripts reference them via `<ProjectReference/>`; packager merges at build.

---

## 3) Template Sync Policy & Verifiers

- **RELAXED (default):** schema/invariants enforced; `.csproj` drift warns only.
- **STRICT:** `.csproj` drift fails.

**Run locally:**

```bash
chmod +x tools/verify-templates-sync.sh
./tools/verify-templates-sync.sh            # RELAXED
MODE=STRICT ./tools/verify-templates-sync.sh # STRICT
```

```powershell
$env:MODE='RELAXED'; pwsh ./tools/Verify-TemplatesSync.ps1
$env:MODE='STRICT';  pwsh ./tools/Verify-TemplatesSync.ps1
```

**CI behavior:** PRs always run RELAXED. Add label `strict-template-sync` to run STRICT. Branch protection requires **Template Sync (gate)**.

---

## 4) Scaffolding New Submodules

Use scaffolders to create submodules from templates.

**Bash**

```bash
# PB script
tools/scaffold-submodule.sh pbscript Scripts/MyScript https://github.com/you/MyScript.git MyScript --sln SE-VIOS-DevFramework.sln --readme
# Mixin
tools/scaffold-submodule.sh mixin Mixins/Modules/Power https://github.com/you/Power.git Power --class PowerModule --sln SE-VIOS-DevFramework.sln --readme
```

**PowerShell**

```powershell
# PB script
pwsh ./tools/Scaffold-Submodule.ps1 -Kind pbscript -DestPath Scripts/MyScript -RemoteUrl https://github.com/you/MyScript.git -ProjectName MyScript -Sln SE-VIOS-DevFramework.sln -Readme
# Mixin
pwsh ./tools/Scaffold-Submodule.ps1 -Kind mixin -DestPath Mixins/Modules/Power -RemoteUrl https://github.com/you/Power.git -ProjectName Power -ClassName PowerModule -Sln SE-VIOS-DevFramework.sln -Readme
```

Notes:

- `__NAME__` and `__CLASS__` replaced; `// SCAFFOLD-STRIP` blocks removed.
- PB scripts require `public partial class Program : MyGridProgram`.
- Mixins must declare `partial class Program` (no base/visibility), not inheriting `MyGridProgram`.

---

## 5) Coding Rules

- **Enclosure:** all code (except `using`) inside:

  ```csharp
  namespace IngameScript { partial class Program { /* code */ } }
  ```

- **C# 6 only**; .NET Framework 4.8.
- **VRage-first** APIs.
- Use coroutines/state machines, pooled allocations, and tick budgeting.
- Throttle UI (default `Update10`).
- Messaging via `VIOSAddress`/`VIOSPacket`.
- Persistence: PB `Storage` + `Me.CustomData`.
- Branding: uppercase VIOS for core types; modules/components neutral.

---

## 6) What to Read First

- `docs/architecture/VIOS-Architecture.md`
- `docs/prompts/VIOS-Prompt-Reusable.md`
- `docs/policies/VIOS-Branding-Extension-Policy.md`
- `docs/policies/VIOS-Template-Sync-Policy.md`
- `tools/check-architecture.ps1`

---

## 7) Task Workflow (for AI Agents)

1. Open a brief under `codex/tasks/`.
2. Keep this file and the architecture doc open.
3. Implement in mixins or PB project.
4. Run local checks (hooks, license header, check-architecture, verifier, msbuild).
5. Open a PR; CI posts violations.

---

## 8) Acceptance (PR Checklist)

A PR is acceptable when:

- Builds on Windows with .NET SDK 9 + MSBuild (Release).
- Code inside `IngameScript` / `partial class Program`.
- C# 6 only; PB whitelist-safe; VRage-first.
- License header present.
- Naming rules satisfied.
- Budgets respected; no hot-path allocations.
- PB projects wire mixins via `<ProjectReference/>`.
- **Template Sync (gate)** passes.

---

## 9) Example Bootstrap (PB script)

```csharp
namespace IngameScript {
  public partial class Program : MyGridProgram {
    IVIOSKernel _kernel; IEnv _env; IConfig _cfg;
    public Program() {
      _env = new Env(this); _cfg = new IniConfig(this); _kernel = new VIOSKernel();
      _kernel.Init(_env, _cfg);
      _kernel.RegisterModule(new PowerModule());
      _kernel.RegisterModule(new ScreenManagerModule());
      _kernel.Start(UpdateFrequency.Update10 | UpdateFrequency.Update100);
    }
    public void Save() { _kernel.Save(); }
    public void Main(string argument, UpdateType updateSource) {
      try { _kernel.Tick(updateSource, argument); }
      catch (System.Exception ex) { Echo("VIOS ERROR: " + ex.Message); }
    }
  }
}
```

---

## 10) CI & Guardrails

- Build CI: `.github/workflows/ci.yml` runs `tools/check-architecture.ps1` and builds.
- **Template Sync:** `.github/workflows/verify-templates-sync.yml` runs RELAXED; STRICT when labeled. **Template Sync (gate)** is required.
- Pre-commit hooks stamp MIT headers.
- Badges in `README.md` show CI + Template Sync status.

---

## 11) License & Header Template

- License: **MIT** (`LICENSE`) — Copyright © 2025 **geho / Thorbergr**.
- Header template: `tools/license_header.tmpl` (synced with LICENSE).
