# VIOS Prompt — Reusable Template (MDK² Layout)

Use this template to kick off **new chats** for Space Engineers (MDK²-SE) work on **Viking Industries Operating System (VIOS)** or related modules. It standardizes context, constraints, defaults, and the expected response format so you get consistent, production-grade outputs.

---

## 0) How to Use

- Fill the **placeholders** like `{{project_name}}`, `{{mode}}`, etc.
- Paste the whole prompt into a new chat.
- If info is missing, the assistant must: **(a)** use defaults from Section 6; **(b)** explicitly list assumptions.

---

## 1) Identity & Scope

**Project:** {{project\_name | Viking Industries Operating System (VIOS)}}
**Context:** Space Engineers **Programmable Block** script using **MDK²-SE** in **VS Code**
**Languages/Targets:** `netframework48`, **C# 6** (no newer features), VRage API first.

**Modes (choose one or more):**

- `ARCHITECT`: propose interfaces, classes, and relationships; provide diagrams.
- `CODE-SKELETON`: emit compilable C# skeletons (no external usings beyond VRage & MDK references) inside `IngameScript.Program`.
- `MODULE`: design/implement a specific module (e.g., Airlock, Power).
- `REVIEW`: critique and optimize provided code for PB whitelist, performance, and robustness.
- `DOCS`: write developer docs and CustomData examples.

**Selected mode(s):** {{mode | ARCHITECT}}

---

## 2) References (MDK²-SE)

- MDK²-SE Repo: [https://github.com/malforge/mdk2](https://github.com/malforge/mdk2)
- MDK²-SE Wiki: [https://github.com/malforge/mdk2/wiki](https://github.com/malforge/mdk2/wiki)
- MDK²-SE using VS Code: [https://github.com/malforge/mdk2/wiki/Getting-Started-using-VSCode](https://github.com/malforge/mdk2/wiki/Getting-Started-using-VSCode)
- PB Whitelist: [https://github.com/malforge/mdk2/blob/main/Source/Mdk.PbAnalyzers/pbwhitelist.dat](https://github.com/malforge/mdk2/blob/main/Source/Mdk.PbAnalyzers/pbwhitelist.dat)
- Legacy MDK-SE hints: [https://github.com/malware-dev/MDK-SE/wiki](https://github.com/malware-dev/MDK-SE/wiki) (API Index, Coroutines, Handling Args)

_(These links are context; the assistant should favor VRage types and the PB whitelist.)_

---

## 3) Hard Constraints (must-haves)

1. **Code enclosure:** All generated code (except `using`) lives inside:

   ```csharp
   namespace IngameScript
   {
       partial class Program
       {
           // generated code here
       }
   }
   ```

2. **MDK²-SE project config:** Target `netframework48`, `LangVersion=6` (C# 6), include `Mal.Mdk2.*` packages.
3. **VRage-first:** Prefer VRage/SE APIs over .NET standard library when options exist.
4. **Top-level safety:** Wrap the PB `Main()` driver or kernel `Tick()` in `try/catch`; surface errors to a Debug LCD and `Echo`.
5. **Coroutines & State Machines:** Use extensively to spread work across ticks.
6. **Pooling & Queues:** Avoid `new` in hot paths; use pooled buffers/objects and bounded queues.
7. **Budgets:** Track **TIC** (`Runtime.CurrentInstructionCount`) and **Call Depth** (`Runtime.CurrentCallChainDepth`); **yield** at thresholds.
8. **Tick cadence:** Handle `Update1`, `Update10`, `Update100`, `UpdateOnce` and track UTC time per tick.
9. **Messaging:** Unify local events and IGC WAN/LAN messaging (unicast/multicast/broadcast) with a simple address/packet model.
10. **UI:** Provide LCD widgets (header/footer/spinner/progress/2D diag/list/table); allow multi-surface mosaics; layouts via `CustomData` using **MyIni**, compatible with _Automatic LCDs 2_ syntax.
11. **Persistence:** Use PB `Storage` and `Me.CustomData` (INI sections) for config and state.
12. **Whitelist compliance:** Use only PB-allowed APIs; warn if a requested feature would violate it.
13. **Branding:** **VIOS** uppercase in **class/interface/struct** names containing the OS name; variables may use lowercase `vios`. **Modules and Components should keep neutral class names** (no VIOS prefix) while implementing `IVIOSModule`.
14. **Project Types:** Use **`mdk2pbscript`** for **PB scripts** under `Scripts/` and **`mdk2mixin`** for reusable **Core**, **Modules**, and **Components** under `Mixins/`. PB scripts reference needed mixins via `<ProjectReference/>` and the packager merges sources.

---

## 4) Expected Deliverables (by mode)

### ARCHITECT

- Interface & class hierarchy with concise responsibilities.
- Subsystem boundaries: **Kernel**, **Scheduler**, **EventBus**, **MessageRouter**, **Pools**, **UI**, **Storage/Config**, **Stats**, **Modules**.
- **Mermaid diagrams**: layered overview, class diagram, tick sequence, messaging path, module state machine.
- Repository layout reflecting **mdk2pbscript**/**mdk2mixin** split.

### CODE-SKELETON

- Compilable C# 6 skeletons placed inside `IngameScript.Program` (no external namespaces beyond allowed VRage & MDK refs).
- Interfaces first, then minimal concrete stubs (no heavy logic), showing pooling and coroutine touchpoints.
- Default `Program()`, `Main()`, `Save()` wiring with kernel facade.
- **Enforce naming rule** in emitted class names containing VIOS (uppercase). **Modules/Components remain neutral.**
- Provide **csproj** examples showing PB→Mixin `ProjectReference` wiring.

### MODULE

- Requirements, states, events, callbacks, IGC endpoints.
- Coroutine-based work slicing; UI widget outputs; CustomData schema.
- Test plan and mock tick traces.
- **Project type:** `mdk2mixin` (module).

### REVIEW

- Identify risks (whitelist, perf, memory churn, reentrancy).
- Give concrete, C# 6-compliant fixes and micro-optimizations.
- Verify **naming rule** compliance and **project type** usage (PB vs mixin).

### DOCS

- Operator guide: config keys, example CustomData, dashboard screenshots (ASCII), message endpoint table.

---

## 5) Output Structure (always follow)

1. **Executive Summary** (bullet list)
2. **Assumptions & Defaults Used** (explicit)
3. **Architecture / Code / Review** (per selected mode)
4. **Diagrams** (Mermaid code blocks)
5. **CustomData Examples** (if applicable)
6. **Validation & Next Steps** (how to build/deploy/test in PB)

_(Keep code blocks minimal and compilable. Avoid long-winded prose.)_

---

## 6) Defaults (use if user omits)

- `UpdateFrequency`: `Update10 | Update100`
- TIC budgets: **Soft=30000**, **Hard=45000**
- Call depth max: **50**
- UI draw cadence: **Update10**
- Network tag: `VIOS`
- Pools: bounded queues with drop-oldest on overflow
- Name service: simple broadcast registry (best-effort)

---

## 7) Repository & Project Layout (canonical)

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
├─ ThirdParty/ (optional vendor mixins)
│  └─ Acme.AirlockPlus/Acme.AirlockPlus.csproj
├─ docs/ (architecture, prompts, policies, steam)
├─ tools/ (license stamper, checks)
├─ .github/ (CI, issue templates)
├─ .githooks/ (pre-commit header stamper)
└─ Directory.Build.props (global LangVersion=6, netframework48)
```

### 7.1 Project Types & Wiring

**PB Script (`mdk2pbscript`)** references mixins it needs:

```xml
<!-- Scripts/VIOS.Bootstrap/VIOS.Bootstrap.csproj -->
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
    <!-- Add components as needed -->
    <ProjectReference Include="..\..\Mixins\Components\Discovery\Discovery.csproj" />
  </ItemGroup>
</Project>
```

**Mixin (`mdk2mixin`)** projects provide sources (no packager):

```xml
<!-- Mixins/VIOS.Core/VIOS.Core.csproj -->
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

**Alternative early-stage setup:** compress to a few mixins (`VIOS.Core`, `VIOS.Modules`, `VIOS.Components`) and split later as contributions grow.

---

## 8) Quality Gates (the assistant must enforce)

- **Whitelist compliance**: reject/replace disallowed APIs; prefer `MyIni`, `IMyTextSurface`, `MySprite`, `IMyIntergridCommunicationSystem`.
- **C# 6 only**: no `async/await`, tuples, pattern matching, Span, etc.
- **Clarity-first types**: avoid `var` when it harms readability.
- **No allocations in hot paths**: pre-size `StringBuilder`, reuse lists/arrays, pooled packets/events.
- **Budget-aware loops**: check TIC/depth inside scans; yield via scheduler tokens.
- **Deterministic drawing cadence**: throttle `DrawFrame` to configured cadence.
- **Error surfacing**: single consolidated error line on console + optional debug LCD.
- **Branding rule check**: **class names** using the OS name must use **VIOS** uppercase; **modules/components** keep neutral class names; variables may use lowercase `vios`.
- **Project types**: PB code in `mdk2pbscript`; Core/Modules/Components in `mdk2mixin` with PB→Mixin `ProjectReference` wiring.

---

## 9) Requested Output (fill-in)

- **Primary Goal:** {{goal | Propose interface/class architecture and diagrams for VIOS}}
- **Specific Focus Areas:** {{focus | Messaging model, Scheduler, UI widgets, Module API}}
- **Modules to include:** {{modules | Power, ScreenMgr, Airlock, Cargo, Production}}
- **Non-goals:** {{non\_goals | Multiplayer sync, heavy serialization}}

---

## 10) Example Invocation

> _Copy, edit placeholders, paste into new chat:_

```
Project: Viking Industries Operating System (VIOS)
Mode: ARCHITECT, CODE-SKELETON
Goal: Design the kernel interfaces and deliver a compilable C#6 skeleton that obeys MDK²-SE constraints.
Focus: Coroutine scheduler, event/message bus, TIC/depth guardrails, LCD widgets.
Include: Power and ScreenMgr neutral modules (as mdk2mixin projects), plus any required Components mixins.
Constraints: PB scripts are mdk2pbscript; Core/Modules/Components are mdk2mixin; PB references mixins via ProjectReference. Enforce naming rule — VIOS uppercase in all class names; variables may use lowercase; modules/components use neutral class names.
Use defaults from Sections 6–7. Follow Output Structure in Section 5.
Ensure all code is inside IngameScript.Program, with try/catch at top level and VRage-first APIs.
Produce Mermaid diagrams.
```

---

## 11) Optional: Naming & Style Examples

```csharp
// Class/interface names containing OS name must use uppercase VIOS
class VIOSKernel {}
interface IVIOSModule {}
struct VIOSContext {}
struct VIOSPacket {}

// Variables/fields may use lowercase
var viosKernel = new VIOSKernel();
VIOSKernel _viosKernel;

// Neutral module class names (no VIOS prefix)
class PowerModule : IVIOSModule { /* ... */ }
class ScreenManagerModule : IVIOSModule { /* ... */ }
```

---

## 12) Acceptance Checklist (for the assistant)

- [ ] Follow Output Structure (Section 5)
- [ ] Use defaults when unspecified; list assumptions
- [ ] Code blocks compile under C# 6 with MDK² references
- [ ] No non-whitelisted APIs
- [ ] Mermaid diagrams render
- [ ] UI and messaging boundaries are clear
- [ ] **Class names use uppercase VIOS**; variables may use lowercase; **modules/components neutral**
- [ ] **PB uses mdk2pbscript; Core/Modules/Components use mdk2mixin; PB→Mixin wired with ProjectReference**
- [ ] Next steps provided (build/deploy/test)
