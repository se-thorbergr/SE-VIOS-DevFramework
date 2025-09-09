# AGENTS.md — VIOS Codex Guide

> Version: 2025-09-09 • Owner: **geho** • Project: **Viking Industries Operating System (VIOS)** for Space Engineers (MDK²‑SE)
>
> This file tells coding agents (e.g., GitHub Copilot / Codeium / ChatGPT in VS Code) **how to work in this repo**: layout, rules, tasks, acceptance, and CI. Treat it as the single source of truth during implementation.

---

## 1) Mission & Scope

- Build an extensible _in‑game OS_ for Space Engineers **Programmable Blocks**.
- Use **MDK²‑SE** with **VS Code**; target **.NET Framework 4.8** and **C# 6**.
- **VRage‑first** APIs. PB whitelist compliant. No async/await, tuples, pattern matching, Span, LINQ in hot paths.

**Branding**

- **VIOS** is the OS product brand. **Type names** containing the OS must use uppercase **VIOS** (e.g., `VIOSKernel`, `IVIOSModule`).
- **Modules** and **Components** keep **neutral** class names (no `VIOS` prefix) but implement branded interfaces (e.g., `IVIOSModule`).
- Variables/fields may use lowercase `vios` (e.g., `_viosKernel`).

---

## 2) Repository Layout & Project Types

### Canonical layout

```
<root>/
├─ Scripts/                               # mdk2pbscript (thin PB bootstraps)
│  ├─ VIOS.Bootstrap/                     # reference PB for Workshop
│  │  ├─ Program.cs
│  │  └─ VIOS.Bootstrap.csproj
│  └─ <OtherPB>/...
├─ Mixins/                                # mdk2mixin (reusable source)
│  ├─ VIOS.Core/                          # branded core types only
│  │  ├─ VIOS.cs (kernel/composition)
│  │  ├─ Env.cs, Scheduler.cs, Events.cs, Messaging.cs, Pools.cs
│  │  ├─ UI/Console.cs, UI/Widgets.cs
│  │  ├─ Storage.cs, Modules.cs, Stats.cs
│  │  └─ VIOS.Core.csproj
│  ├─ Components/                         # neutral building blocks
│  │  ├─ Discovery/Discovery.csproj
│  │  ├─ Screen/ScreenPrimitives.csproj
│  │  └─ Network/LightNameService.csproj
│  └─ Modules/                            # neutral feature modules
│     ├─ Power/PowerModule.csproj
│     ├─ ScreenMgr/ScreenManagerModule.csproj
│     └─ (Airlock|Cargo|Production)/...
├─ ThirdParty/                            # optional vendor mixins (git submodules)
├─ docs/                                  # architecture, prompts, policies, steam
├─ codex/                                 # task briefs + acceptance
│  ├─ tasks/ (T-001 … T-004)
│  └─ checklists/PR-acceptance.md
├─ tools/                                 # scaffolders, verifiers, stampers
├─ .github/                               # CI, issue templates
├─ .githooks/                             # pre-commit header stamper
└─ Directory.Build.props                  # global LangVersion=6, netframework48
```

### Project types & wiring

- **PB scripts** are `mdk2pbscript` projects under **Scripts/** and include the MDK² **packager**.
- **Core**, **Modules**, **Components** are `mdk2mixin` projects under **Mixins/** (no packager). PB scripts reference them via `<ProjectReference/>`; the packager merges sources at build time.

**PB example** (`Scripts/VIOS.Bootstrap/VIOS.Bootstrap.csproj`):

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netframework48</TargetFramework>
    <RootNamespace>IngameScript</RootNamespace>
    <LangVersion>6</LangVersion>
    <GenerateAssemblyInfo>false</GenerateAssemblyInfo>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Mal.Mdk2.PbAnalyzers" Version="2.1.13" PrivateAssets="all" />
    <PackageReference Include="Mal.Mdk2.PbPackager" Version="2.1.5" PrivateAssets="all" />
    <PackageReference Include="Mal.Mdk2.References" Version="2.2.4" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="../../Mixins/VIOS.Core/VIOS.Core.csproj" />
    <ProjectReference Include="../../Mixins/Modules/Power/PowerModule.csproj" />
    <ProjectReference Include="../../Mixins/Modules/ScreenMgr/ScreenManagerModule.csproj" />
    <ProjectReference Include="../../Mixins/Components/Discovery/Discovery.csproj" />
  </ItemGroup>
</Project>
```

**Mixin example** (`Mixins/VIOS.Core/VIOS.Core.csproj`):

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netframework48</TargetFramework>
    <RootNamespace>IngameScript</RootNamespace>
    <LangVersion>6</LangVersion>
    <GenerateAssemblyInfo>false</GenerateAssemblyInfo>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Mal.Mdk2.PbAnalyzers" Version="2.1.13" PrivateAssets="all" />
    <PackageReference Include="Mal.Mdk2.References" Version="2.2.4" />
  </ItemGroup>
</Project>
```

---

## 3) Template Sync policy & verifiers (IMPORTANT)

This repo enforces project shape via **template sync** in two modes.

- **RELAXED (default)** — schema/invariants must pass; `.csproj` drift only warns.
- **STRICT** — also fails on `.csproj` (semi‑static) drift.

**Run locally (pick ONE verifier):**

```bash
# Linux/macOS/WSL/Git Bash
chmod +x tools/verify-templates-sync.sh
./tools/verify-templates-sync.sh                 # RELAXED
MODE=STRICT ./tools/verify-templates-sync.sh     # STRICT
```

```powershell
# PowerShell 7+ (Windows or cross‑platform)
$env:MODE='RELAXED'; pwsh ./tools/Verify-TemplatesSync.ps1
$env:MODE='STRICT';  pwsh ./tools/Verify-TemplatesSync.ps1
```

**CI behavior:** PRs always run RELAXED. Add the label **`strict-template-sync`** to also run the STRICT lane. Branch protection requires the gate job **“Template Sync (gate)”** to pass; when STRICT is requested, the gate enforces it.

Policy details: `docs/policies/VIOS-Template-Sync-Policy.md`.

---

## 4) Scaffolding new submodules

Use the scaffolders to create a new Git submodule seeded from templates.

**Bash**

```bash
# PB script (preview)
tools/scaffold-submodule.sh pbscript Scripts/MyScript https://github.com/you/MyScript.git MyScript --dry-run
# PB script (create)
tools/scaffold-submodule.sh pbscript Scripts/MyScript https://github.com/you/MyScript.git MyScript --sln SE-VIOS-DevFramework.sln --readme
# Mixin (preview)
tools/scaffold-submodule.sh mixin Mixins/Modules/Power https://github.com/you/Power.git Power --class PowerModule --dry-run
# Mixin (create)
tools/scaffold-submodule.sh mixin Mixins/Modules/Power https://github.com/you/Power.git Power --class PowerModule --sln SE-VIOS-DevFramework.sln --readme
```

**PowerShell**

```powershell
# PB script (preview)
pwsh ./tools/Scaffold-Submodule.ps1 -Kind pbscript -DestPath Scripts/MyScript -RemoteUrl https://github.com/you/MyScript.git -ProjectName MyScript -DryRun
# PB script (create)
pwsh ./tools/Scaffold-Submodule.ps1 -Kind pbscript -DestPath Scripts/MyScript -RemoteUrl https://github.com/you/MyScript.git -ProjectName MyScript -Sln SE-VIOS-DevFramework.sln -Readme
# Mixin (preview)
pwsh ./tools/Scaffold-Submodule.ps1 -Kind mixin -DestPath Mixins/Modules/Power -RemoteUrl https://github.com/you/Power.git -ProjectName Power -ClassName PowerModule -DryRun
# Mixin (create)
pwsh ./tools/Scaffold-Submodule.ps1 -Kind mixin -DestPath Mixins/Modules/Power -RemoteUrl https://github.com/you/Power.git -ProjectName Power -ClassName PowerModule -Sln SE-VIOS-DevFramework.sln -Readme
```

Notes:

- Tokens `__NAME__` (project) and, for mixins, `__CLASS__` (primary type) are replaced; blocks between `// SCAFFOLD-STRIP-START` … `// SCAFFOLD-STRIP-END` are removed.
- PB scripts require `Program.cs` with `public partial class Program : MyGridProgram`.
- Mixins must have at least one file declaring `partial class Program` (no visibility/base) and **must not** inherit `MyGridProgram`.

---

## 5) Coding Rules (must obey)

- **Enclosure:** all emitted code (except `using`) must be inside:

  ```csharp
  namespace IngameScript { partial class Program { /* code */ } }
  ```

- **C# 6 only**; .NET Framework 4.8. No newer language features.
- **VRage-first:** prefer `IMyTextSurface`, `MySprite`, `IMyIntergridCommunicationSystem`, `MyIni`, etc.
- **Coroutines/State Machines:** spread work across ticks.
- **Pooling/Queues:** no allocations in hot paths; reuse buffers/objects; bounded queues with drop-oldest on overflow.
- **Budgets:** check `Runtime.CurrentInstructionCount` and `CurrentCallChainDepth`; yield at soft/hard thresholds.
- **Ticks:** support `Update1`, `Update10`, `Update100`, `UpdateOnce`; record UTC per tick and per event.
- **UI cadence:** throttle drawing (default `Update10`).
- **Messaging:** unify local events and IGC WAN/LAN with `VIOSAddress`/`VIOSPacket` and unicast/multicast/broadcast.
- **Persistence:** PB `Storage` + `Me.CustomData` via `MyIni`.
- **Branding:** core types must use uppercase **VIOS**; **modules/components** must **not** use the VIOS prefix in type names.

---

## 6) What to read first

- `docs/architecture/VIOS-Architecture.md` — interfaces, diagrams, tick pipeline.
- `docs/prompts/VIOS-Prompt-Reusable.md` — task framing.
- `docs/policies/VIOS-Branding-Extension-Policy.md` — branding & MIT license.
- `docs/policies/VIOS-Template-Sync-Policy.md` — template invariants & CI behavior.
- `tools/check-architecture.ps1` — guardrail checks.

---

## 7) Task workflow (for AI agents)

1. Open a brief under `codex/tasks/` (e.g., `T-001-kernel-skeleton.md`).
2. Keep **this file** and the **architecture doc** open so the agent ingests them as context.
3. Implement inside **mixins** (Modules/Components/Core) or the **PB** project as directed.
4. Run local checks:

   - `git config core.hooksPath .githooks` (once per clone)
   - `pwsh tools/Add-LicenseHeader.ps1` (or `./tools/add_license_header.sh`)
   - `pwsh tools/check-architecture.ps1 -RepoRoot .`
   - One verifier (bash **or** PowerShell) in RELAXED/STRICT (see §3).
   - `msbuild SE-VIOS-DevFramework.sln /p:Configuration=Release /m`

5. Open a PR; CI posts annotations/inline comments for violations.

---

## 8) Acceptance (PR checklist)

A PR is acceptable when:

- Builds on Windows with .NET SDK 9 + MSBuild (Release).
- All source wrapped in `IngameScript` / `partial class Program`.
- C# 6 only; PB whitelist‑safe; VRage‑first.
- License header present (MIT/VIOS banner).
- **Naming rules satisfied**: `VIOS` uppercase in core types; modules/components use neutral names.
- TIC/depth budget checks present in loops; zero allocations in hot paths.
- UI draw cadence throttled (default `Update10`).
- PB project wires mixins via `<ProjectReference/>`; mixins are `mdk2mixin`.
- **Template Sync (gate) passes**: RELAXED always; STRICT also passes if the PR is labeled `strict-template-sync`.

Reference checklist: `codex/checklists/PR-acceptance.md`.

---

## 9) Example bootstrap (PB script)

```csharp
namespace IngameScript
{
  public partial class Program : MyGridProgram
  {
    IVIOSKernel _kernel; IEnv _env; IConfig _cfg;

    public Program()
    {
      _env = new Env(this); _cfg = new IniConfig(this); _kernel = new VIOSKernel();
      _kernel.Init(_env, _cfg);
      _kernel.RegisterModule(new PowerModule());
      _kernel.RegisterModule(new ScreenManagerModule());
      _kernel.Start(UpdateFrequency.Update10 | UpdateFrequency.Update100);
    }

    public void Save() { _kernel.Save(); }

    public void Main(string argument, UpdateType updateSource)
    {
      try { _kernel.Tick(updateSource, argument); }
      catch (System.Exception ex) { Echo("VIOS ERROR: " + ex.Message); }
    }
  }
}
```

---

## 10) CI & Guardrails

- Build CI: `.github/workflows/ci.yml` runs `tools/check-architecture.ps1` and builds the solution.
- **Template Sync**: `.github/workflows/verify-templates-sync.yml` runs RELAXED on all PRs, and STRICT when labeled `strict-template-sync`. The **gate** job `Template Sync (gate)` is the single required check.
- Pre‑commit hooks stamp MIT headers: `.githooks/pre-commit` + scripts in `tools/`.
- Badges in `README.md` reflect CI and Template Sync status.

---

## 11) License & Header template

- License: **MIT** (`LICENSE`) — Copyright © 2025 **geho / Thorbergr**.
- Header template: `tools/license_header.tmpl` (kept in sync with LICENSE owner/year and repo URLs).
