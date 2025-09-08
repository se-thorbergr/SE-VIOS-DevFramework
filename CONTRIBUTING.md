# Contributing to SE-VIOS-DevFramework

Thanks for your interest in extending **Viking Industries Operating System (VIOS)** for Space Engineers!

This project lives in the `se-thorbergr` org and targets **MDK²-SE** with **C# 6 / .NET Framework 4.8**. Please read this file fully before opening a PR.

---

## Brand & Naming

- **Core** types (kernel/scheduler/router/etc.) must use uppercase **VIOS** in type/interface/struct names
  e.g., `VIOSKernel`, `IVIOSModule`, `VIOSContext`, `VIOSPacket`.
- **Modules** and **Components** must keep **neutral class names** (no `VIOS` prefix) while implementing branded interfaces (e.g., `IVIOSModule`).
- Variables/fields may use lowercase `vios` (e.g., `_viosKernel`).

---

## Coding Constraints

- **Target:** `.NET Framework 4.8`, **C# 6** only (no newer features).
- **MDK² layout:**

  - **PB scripts** live under `Scripts/` as **`mdk2pbscript`** projects.
  - **Core**, **Modules**, **Components** live under `Mixins/` as **`mdk2mixin`** projects.
  - PB scripts reference mixins with `<ProjectReference/>`; MDK² packager merges sources.
  - See **docs/policies/VIOS-Template-Sync-Policy.md** for the **Template Sync policy & invariants** (static / semi-static / flexible).

- **Enclosure rule:** All generated code (except `using`) must be inside:

  ```csharp
  namespace IngameScript { partial class Program { /* code */ } }
  ```

- **VRage-first APIs:** Prefer `IMyTextSurface`, `MySprite`, `IMyIntergridCommunicationSystem`, `MyIni`, etc.
- **Performance:** Use coroutines/state machines; avoid allocations in hot paths; use pooling/queues.
- **Budgets:** Check `Runtime.CurrentInstructionCount` and `CurrentCallChainDepth`; yield at soft/hard thresholds.
- **Ticks & Time:** Handle `Update1/10/100/Once`; record UTC per tick and per event.
- **UI:** Draw LCDs at a fixed cadence (default `Update10`); keep frames minimal.
- **Persistence:** Use `Storage` and `Me.CustomData` (MyIni) for config/state.
- **Whitelist:** Only PB-allowed APIs.

---

## License & Headers

- License: **MIT**.
- Headers are auto-stamped from `tools/license_header.tmpl` via pre-commit hooks.
- One-time in your clone:

  ```bash
  git config core.hooksPath .githooks
  chmod +x .githooks/pre-commit tools/add_license_header.sh
  ```

---

## Adding a new submodule (scaffolding)

We ship **scaffolders** that create a new Git submodule and seed it from our templates.

### TL;DR

- **PB script** → `Scripts/<Project>` (requires `Program.cs` with `public partial class Program : MyGridProgram`)
- **Mixin** → `Mixins/<Area>/<Project>` (no fixed filename; at least one `.cs` must declare `partial class Program`)

Both scaffolders support:

- `--readme` to seed a README
- `--sln <file.sln>` to add project(s) to the solution
- `--branch <name>` to set the submodule’s tracked branch (default `main`)
- `--dry-run` to preview actions (no changes)
- `--class <ClassName>` **(mixin only)** to set the primary type and file name

Scaffolders automatically:

- Replace tokens `__NAME__` (project/repo) and, for mixins, `__CLASS__` (primary type)
- Strip blocks between `// SCAFFOLD-STRIP-START` … `// SCAFFOLD-STRIP-END` from copied files
- Normalize line endings and commit inside the submodule (push is best-effort)

#### Bash (Linux/macOS/WSL/Git Bash)

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

#### PowerShell (Windows / cross-platform)

```powershell
# PB script (preview)
pwsh ./tools/Scaffold-Submodule.ps1 -Kind pbscript `
  -DestPath Scripts/MyScript `
  -RemoteUrl https://github.com/you/MyScript.git `
  -ProjectName MyScript `
  -DryRun

# PB script (create)
pwsh ./tools/Scaffold-Submodule.ps1 -Kind pbscript `
  -DestPath Scripts/MyScript `
  -RemoteUrl https://github.com/you/MyScript.git `
  -ProjectName MyScript `
  -Sln SE-VIOS-DevFramework.sln -Readme

# Mixin (preview)
pwsh ./tools/Scaffold-Submodule.ps1 -Kind mixin `
  -DestPath Mixins/Modules/Power `
  -RemoteUrl https://github.com/you/Power.git `
  -ProjectName Power `
  -ClassName PowerModule `
  -DryRun

# Mixin (create)
pwsh ./tools/Scaffold-Submodule.ps1 -Kind mixin `
  -DestPath Mixins/Modules/Power `
  -RemoteUrl https://github.com/you/Power.git `
  -ProjectName Power `
  -ClassName PowerModule `
  -Sln SE-VIOS-DevFramework.sln -Readme
```

**Notes & expectations**

- **PB Scripts**: our template requires `Program.cs` (entry point), and verifiers enforce the enclosure signature.
- **Mixins**: filename freedom. Our template seeds a single file `__NAME__.cs` → `<ClassName>.cs` that declares `partial class Program` inside `namespace IngameScript`. You can add more `.cs` files; at least one must have that enclosure. Mixins **must not** inherit `MyGridProgram`.
- First push from the submodule may be blocked by remote protections; this does **not** fail scaffolding.

---

## Workflow

1. **Discuss first:** Open an issue using the **Module Proposal** or **Bug Report** templates in `.github/ISSUE_TEMPLATE/`.
2. **Branch:** `feature/<short-name>` from `main`.
3. **Implement:**

   - Place PB code in `Scripts/…` (**mdk2pbscript**).
   - Place Core/Modules/Components in `Mixins/…` (**mdk2mixin**).
   - Keep code inside `IngameScript.Program`.

4. **Local checks:**

   ```bash
   # License headers / policy checks
   pwsh tools/Add-LicenseHeader.ps1         # or ./tools/add_license_header.sh
   pwsh tools/check-architecture.ps1 -RepoRoot .

   # Run exactly ONE template verifier depending on your environment:
   # Linux/macOS/WSL/Git Bash:
   chmod +x tools/verify-templates-sync.sh
   ./tools/verify-templates-sync.sh                 # RELAXED (default)
   MODE=STRICT ./tools/verify-templates-sync.sh     # STRICT

   # Windows (PowerShell 7+ recommended):
   pwsh ./tools/Verify-TemplatesSync.ps1            # RELAXED (default)
   $env:MODE='STRICT'; pwsh ./tools/Verify-TemplatesSync.ps1

   # Build (Windows)
   msbuild SE-VIOS-DevFramework.sln /p:Configuration=Release /m
   ```

5. **PR:** Push and open a PR to `main`. CI will annotate violations and post inline comments.

   - CI always runs **RELAXED** verification.
   - Add label **`strict-template-sync`** to your PR to also run **STRICT** verification (semi-static `.csproj` drift becomes fail).

---

## Style

- Prefer explicit types over `var` where clarity helps.
- Zero allocations in tick loops; reuse `StringBuilder` and lists.
- Keep method bodies small; use interfaces/classes (not free functions) to model responsibilities.
- Avoid LINQ, reflection, and exceptions in hot paths.

---

## PB Project Types (quick reference)

- **PB script** (`mdk2pbscript`): includes `Mal.Mdk2.PbPackager` + `Mal.Mdk2.PbAnalyzers` + `Mal.Mdk2.References`. References mixins via `<ProjectReference/>`.
- **Mixin** (`mdk2mixin`): includes `Mal.Mdk2.PbAnalyzers` + `Mal.Mdk2.References`; **forbid** `Mal.Mdk2.PbPackager`; source-only.

---

## Module Skeleton

See the starter neutral modules:

- `Mixins/Modules/ScreenMgr/ScreenManagerModule.csproj` + `ScreenManagerModule.cs`
- `Mixins/Modules/Power/PowerModule.csproj` + `PowerModule.cs`

Each module should implement:

```csharp
namespace IngameScript {
  partial class Program {
    class YourModule : IVIOSModule {
      public string Name { get { return "Your.ModuleId"; } }
      public void Init(VIOSContext ctx, IModuleRegistrar reg) { }
      public void Start(VIOSContext ctx) { }
      public void Tick(VIOSContext ctx) { }          // lightweight; slice heavy work into coroutines
      public void Stop(VIOSContext ctx) { }
      public void OnMessage(ref VIOSPacket p, VIOSContext ctx) { }
      public void DescribeStatus(StringBuilder sb) { }
    }
  }
}
```

---

## Template sync verification (local)

This repo enforces a lightweight **MDK² project** template policy. See:
`docs/policies/VIOS-Template-Sync-Policy.md`.

You only need **one** verifier depending on your environment:

- **Bash (Linux/macOS/WSL/Git Bash):** `tools/verify-templates-sync.sh`
- **PowerShell 7+ (Windows or cross-platform):** `tools/Verify-TemplatesSync.ps1`

Both default to **RELAXED** mode (schema/invariants must pass; `.csproj` drift only warns). Use **STRICT** to also fail on `.csproj` drift.

### What is checked

- **Static files** (must match templates; normalized line endings):
  `.gitignore`, `.gitattributes`, `.editorconfig`, `Directory.Build.props`, and PB `*.mdk.ini` (must contain `type=programmableblock`).
- **Semi-static** (`*.csproj`, exactly one per submodule):

  - **PB scripts**: `<Mdk2ProjectType>mdk2pbscript</Mdk2ProjectType>`; require `Mal.Mdk2.PbPackager`, `Mal.Mdk2.PbAnalyzers`, `Mal.Mdk2.References`.
  - **Mixins**: `<Mdk2ProjectType>mdk2mixin</Mdk2ProjectType>`; **forbid** `Mal.Mdk2.PbPackager`; require `Mal.Mdk2.PbAnalyzers`, `Mal.Mdk2.References`.
  - Extra `ItemGroup`/`PropertyGroup`, extra packages, and `ProjectReference`s are allowed (drift shown; only fails in STRICT).

- **Code enclosure**

  - **PB (`Scripts/*`)**: file `Program.cs` must contain `public partial class Program : MyGridProgram`.
  - **Mixins (`Mixins/*`)**: at least one `*.cs` must declare `partial class Program` (no visibility/base). **No** file may inherit `MyGridProgram`.

### Interpreting output

```
===== verify-templates-sync: Summary =====
Missing files: none
Drift vs template (N):           # differs from template (allowed in RELAXED)
Validation issues (M):           # invariant violations (always fail)
==========================================
```

- **Missing files** → create or re-scaffold from `tools/templates/*`.
- **Validation issues** → must be fixed (wrong `<Mdk2ProjectType>`, missing packages, enclosure rule broken, multiple `.csproj`/`.mdk.ini`, etc.).
- **Drift vs template** → inspect grouped diffs; acceptable in RELAXED if only semi-static differences; use STRICT to enforce zero drift.

### Common pitfalls & fixes

- **Line endings / BOM**: repo enforces via `.gitattributes`. If you see noisy diffs, normalize the working tree:

  ```bash
  git rm --cached -r . && git reset --hard
  ```

- **Program.cs enclosure missing**: ensure the exact signatures above (PB vs mixin rules differ).
- **Package set**: PB must include _Packager + Analyzers + References_; mixins only _Analyzers + References_.
- **One file each**: keep exactly one `.csproj` and one `.mdk.ini` per submodule.
- **Submodules**: initialize before running verifiers:

  ```bash
  git submodule update --init --recursive
  ```

### CI behavior

- PRs run the verifiers in **RELAXED** by default as a required check.
- Apply label **`strict-template-sync`** to request a STRICT run on your PR.
- You can also run STRICT manually via **Actions → Template Sync → Run workflow → `strict=true`**.

---

## PR Acceptance Checklist

- [ ] Builds (Windows) with .NET SDK 9 + MSBuild (Release)
- [ ] Code wrapped in `namespace IngameScript { partial class Program { ... } }`
- [ ] C# 6 only; PB whitelist-safe; VRage-first
- [ ] License header present (MIT / VIOS banner)
- [ ] **Branding**: VIOS uppercase in core types; **modules/components neutral**
- [ ] TIC/depth checks in long loops; no allocations in tick paths
- [ ] UI drawing cadence throttled (default `Update10`)
- [ ] PB→Mixin wiring via `<ProjectReference/>`; mixins are `mdk2mixin`
- [ ] **Template Sync** passes (RELAXED minimum). If your PR has **`strict-template-sync`**, ensure STRICT is clean.

---

## Helpful docs

- `docs/architecture/VIOS-Architecture.md`
- `docs/prompts/VIOS-Prompt-Reusable.md`
- `docs/policies/VIOS-Branding-Extension-Policy.md`
- `docs/policies/VIOS-Template-Sync-Policy.md`
- `AGENTS.md` (Codex guide)

Thanks for contributing!
