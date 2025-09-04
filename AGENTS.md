# AGENTS.md — VIOS Codex Guide

> Version: 2025-09-03 • Owner: **geho** • Project: **Viking Industries Operating System (VIOS)** for Space Engineers (MDK²-SE)
>
> This file tells coding agents (Codex in VS Code) **how to work in this repo**: layout, rules, tasks, acceptance, and CI. Treat it as the single source of truth during implementation.

---

## 1) Mission & Scope

* Build an extensible *in‑game OS* for Space Engineers **Programmable Blocks**.
* Use **MDK²-SE** with **VS Code**; target **.NET Framework 4.8** and **C# 6**.
* **VRage-first** APIs. PB whitelist compliant. No async/await, tuples, pattern matching, Span, LINQ in hot paths.

**Branding:**

* **VIOS** is the OS product brand. **Type names** containing the OS must use uppercase **VIOS** (e.g., `VIOSKernel`, `IVIOSModule`).
* **Modules and Components** keep **neutral** class names (no VIOS prefix) but implement branded interfaces (e.g., `IVIOSModule`).
* Variables/fields may use lowercase `vios` (e.g., `_viosKernel`).

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
│  ├─ tasks/
│  │  ├─ T-001-kernel-skeleton.md
│  │  ├─ T-002-scheduler.md
│  │  ├─ T-003-router-igc.md
│  │  └─ T-004-modules-screenmgr-power.md
│  └─ checklists/PR-acceptance.md
├─ tools/                                 # license stamper, policy checks
├─ .github/                               # CI, issue templates
├─ .githooks/                             # pre-commit header stamper
└─ Directory.Build.props                  # global LangVersion=6, netframework48
```

### Project types & wiring

* **PB scripts** are `mdk2pbscript` projects under **Scripts/** and include the MDK² **packager**.
* **Core**, **Modules**, **Components** are `mdk2mixin` projects under **Mixins/** (no packager). PB scripts reference them via `<ProjectReference/>`; the packager merges sources at build time.

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
    <ProjectReference Include="..\..\Mixins\VIOS.Core\VIOS.Core.csproj" />
    <ProjectReference Include="..\..\Mixins\Modules\Power\PowerModule.csproj" />
    <ProjectReference Include="..\..\Mixins\Modules\ScreenMgr\ScreenManagerModule.csproj" />
    <ProjectReference Include="..\..\Mixins\Components\Discovery\Discovery.csproj" />
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

## 3) Coding Rules (must obey)

* **Enclosure:** All emitted code (except `using`) must be inside:

  ```csharp
  namespace IngameScript { partial class Program { /* code */ } }
  ```
* **C# 6 only**; .NET Framework 4.8. No newer language features.
* **VRage-first**: prefer `IMyTextSurface`, `MySprite`, `IMyIntergridCommunicationSystem`, `MyIni`, etc.
* **Coroutines/State Machines**: spread work across ticks.
* **Pooling/Queues**: no allocations in hot paths; reuse buffers/objects; bounded queues with drop-oldest on overflow.
* **Budgets**: check `Runtime.CurrentInstructionCount` and `CurrentCallChainDepth`; yield at soft/hard thresholds.
* **Ticks**: support `Update1`, `Update10`, `Update100`, `UpdateOnce`; record UTC per tick and per event.
* **UI cadence**: throttle drawing (default `Update10`).
* **Messaging**: unify local events and IGC WAN/LAN with `VIOSAddress`/`VIOSPacket` and unicast/multicast/broadcast.
* **Persistence**: PB `Storage` + `Me.CustomData` via `MyIni`.
* **Branding**: core types must use uppercase **VIOS**; **modules/components** should **not** use the VIOS prefix.

---

## 4) What to read first

* `docs/architecture/VIOS-Architecture.md` — interfaces, diagrams, tick pipeline.
* `docs/prompts/VIOS-Prompt-Reusable.md` — task framing.
* `docs/policies/VIOS-Branding-Extension-Policy.md` — branding & MIT license.
* `tools/check-architecture.ps1` — policy checks run in CI.

---

## 5) Task workflow (Codex)

1. Open a brief under `codex/tasks/` (e.g., `T-001-kernel-skeleton.md`).
2. In the Codex panel, start **Code** on that brief. Keep this `AGENTS.md` and the architecture doc open so Codex picks them up as context.
3. Implement **inside mixins** (Modules/Components/Core) or **the PB project** per the brief.
4. Run local checks:

   * `git config core.hooksPath .githooks` (once per clone)
   * `pwsh tools/Add-LicenseHeader.ps1` (or `./tools/add_license_header.sh`)
   * `pwsh tools/check-architecture.ps1 -RepoRoot .`
   * `msbuild SE-VIOS-DevFramework.sln /p:Configuration=Release /m`
5. Open a PR; CI posts annotations/inline comments on violations.

---

## 6) Acceptance (PR checklist)

A PR is acceptable when:

* Builds on Windows with .NET SDK 9 + MSBuild (Release).
* All source wrapped in `IngameScript` / `partial class Program`.
* C# 6 only; PB whitelist-safe; VRage-first.
* License header present (MIT/VIOS banner).
* **Naming rules satisfied**: `VIOS` uppercase in core types; neutral names for modules/components.
* TIC/depth budget checks present in loops; zero allocations in hot paths.
* UI draw cadence throttled (default `Update10`).
* PB project wires mixins via `<ProjectReference/>`; mixins stay `mdk2mixin`.

Reference checklist file: `codex/checklists/PR-acceptance.md`.

---

## 7) Do / Don’t

**Do**

* Use explicit types where clarity matters.
* Slice heavy scans across ticks via coroutines.
* Keep message payloads compact strings (INI/delimited), not heavy serializers.
* Respect CI warnings; fix before merging.

**Don’t**

* Introduce non-whitelisted APIs or heavy allocations in `Tick()`.
* Use `async/await`, LINQ in hot paths, or features beyond C# 6.
* Brand third‑party modules with the VIOS prefix.

---

## 8) Example bootstrap (PB script)

```csharp
namespace IngameScript
{
  partial class Program
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
      catch (Exception ex) { Echo("VIOS ERROR: " + ex.Message); }
    }
  }
}
```

---

## 9) CI & Guardrails

* CI: `.github/workflows/ci.yml` builds and runs `tools/check-architecture.ps1`.
* Inline PR comments and annotations are posted when policy violations are found (naming, enclosure, headers, etc.).
* Pre-commit hooks stamp MIT headers: `.githooks/pre-commit` + scripts in `tools/`.
* README badge for CI status is maintained at the top of `README.md`.

---

## 10) Contact & Ownership

* Maintainer: **geho** (GitHub)
* Brands: **Viking Industries (VI)**, **Viking Industries Operating System (VIOS)** — owned by **Thorbergr**; code licensed **MIT**.


