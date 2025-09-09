[![CI](https://github.com/se-thorbergr/SE-VIOS-DevFramework/actions/workflows/ci.yml/badge.svg)](https://github.com/se-thorbergr/SE-VIOS-DevFramework/actions/workflows/ci.yml)
[![Template Sync](https://github.com/se-thorbergr/SE-VIOS-DevFramework/actions/workflows/verify-templates-sync.yml/badge.svg)](https://github.com/se-thorbergr/SE-VIOS-DevFramework/actions/workflows/verify-templates-sync.yml)

# SE-VIOS-DevFramework

Space Engineers **Programmable Block** framework for building **VIOS**-powered scripts with **MDK²‑SE** + **VS Code**.

> Built by Space Engineers fans, for Space Engineers fans. Drop in, wire modules, and make your grid feel alive. ⚙️🚀

- **VIOS** = _Viking Industries Operating System_ (the tiny "OS" that runs inside your PB)
- **Why?** Slice heavy logic across ticks, pass messages between modules/IGC, draw tidy HUDs, and stay under the PB instruction budget without tears.

---

## Table of Contents

- [SE-VIOS-DevFramework](#se-vios-devframework)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [Repository Layout](#repository-layout)
  - [Scaffold New PB/Mixin](#scaffold-new-pbmixin)
  - [Project Types (MDK²)](#project-types-mdk)
  - [Quick Start (VS Code / dotnet)](#quick-start-vs-code--dotnet)
  - [Build \& Package to Space Engineers](#build--package-to-space-engineers)
  - [Coding Rules \& Naming](#coding-rules--naming)
  - [Docs \& Architecture](#docs--architecture)
    - [Validate Architecture Doc (headless‑friendly)](#validate-architecture-doc-headlessfriendly)
  - [Contributing](#contributing)
  - [License \& Branding](#license--branding)
  - [Troubleshooting](#troubleshooting)
  - [FAQ](#faq)
  - [Credits](#credits)
    - [Maintainer Quick Commands](#maintainer-quick-commands)

---

## Features

- **Tiny OS kernel** (VIOSKernel) with lifecycle: `Init → Register → Start → Tick → Save`
- **No-lag coroutines**: split big jobs across ticks to dodge the instruction cap
- **Plug‑and‑play modules**: neutral‑named modules implementing `IVIOSModule` (starter: Power, ScreenMgr)
- **In‑game HUD bits**: header/footer/status/spinner/progress/tables/sparklines on LCDs
- **Messaging that just works**: local bus + IGC (unicast/multicast/broadcast)
- **Config & save**: tweak via `Me.CustomData` (`MyIni`), persist via `Storage`
- **Guardrails**: build/CI checks + architecture doc with Mermaid diagrams
- **Template Sync gate**: CI verifies each PB/Mixin against our templates. Default **RELAXED** mode; add the PR label **`strict-template-sync`** to also run the **STRICT** lane (fails on `.csproj` drift). See **docs/policies/VIOS-Template-Sync-Policy.md**.

> TL;DR: smoother ticks, cleaner code, happier grid.

---

## Repository Layout

```
<root>/
├─ Scripts/                      # mdk2pbscript (thin PB bootstraps you paste into SE)
│  ├─ VIOS.Bootstrap/
│  ├─ VIOS.DevSandbox/
│  └─ VIOS.Minimal/
│
├─ Mixins/                       # mdk2mixin (merged into PB at build)
│  ├─ VIOS.Core/                 # Kernel / scheduler / router / UI primitives
│  ├─ Components/                # Discovery / screen helpers / light name service
│  └─ Modules/                   # Power / ScreenMgr / your next idea
│
├─ docs/                         # Canonical architecture & friends
│  └─ architecture/VIOS-Architecture.md
│
├─ codex/                        # Seed tasks for AI‑assisted sessions
├─ tools/                        # Scaffolders, verifiers, license stampers
├─ .githooks/                    # Pre‑commit header stamping
└─ .github/                      # CI, issue & PR templates
```

> Start with `docs/architecture/VIOS-Architecture.md` to see how the parts snap together.

---

## Scaffold New PB/Mixin

> Use our scaffolders to create a new Git submodule and seed it from templates. Tokens `__NAME__` (project) and `__CLASS__` (mixin primary type) are replaced, and `// SCAFFOLD-STRIP` blocks are removed.

**Bash (Linux/macOS/WSL/Git Bash)**

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

**PowerShell (Windows / cross‑platform)**

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

**Expectations**

- **PB Scripts**: template requires `Program.cs` with `public partial class Program : MyGridProgram`.
- **Mixins**: filename freedom. At least one `.cs` must declare `partial class Program` (no visibility/base). Mixins **must not** inherit `MyGridProgram`.
- First push from the submodule may be blocked by repo protections; scaffolding will still complete.

---

## Project Types (MDK²)

**PB Scripts** (`mdk2pbscript`) — the entry you paste into SE.

```csharp
namespace IngameScript
{
    public partial class Program : MyGridProgram
    {
        // entrypoint
    }
}
```

**Mixins** (`mdk2mixin`) — reusable code merged at pack time.

```csharp
namespace IngameScript
{
    partial class Program
    {
        // mixin code
    }
}
```

> **Rule of thumb:** only the PB script inherits `MyGridProgram`. **Mixins must not inherit `MyGridProgram`.**

---

## Quick Start (VS Code / dotnet)

**You’ll need**

- .NET SDK 9.0 (build host; target is still `netframework48`)
- (Optional) Node + Chromium for doc checks
- Space Engineers installed (for Packager deploy)

**Spin it up**

```bash
dotnet --info
# open in VS Code
code SE-VIOS-DevFramework.code-workspace
# build everything
dotnet build SE-VIOS-DevFramework.sln -c Release
```

Packager will merge mixins and drop PB scripts into your SE local scripts folder (Windows build host) or Proton equivalent.

> Want the shortest runway? Tweak `Scripts/VIOS.Minimal/Program.cs`, build, paste into your PB, go.

---

## Build & Package to Space Engineers

1. Wire modules in a PB script under **Scripts/** (e.g., register `PowerModule`, `ScreenManagerModule`).

2. Build:

   ```bash
   dotnet build SE-VIOS-DevFramework.sln -c Release
   ```

3. In SE: Programmable Block → **Edit** → **Browse Local Scripts** → pick your packaged script → **OK**.

Tip: keep heavy scans in **coroutines**; the kernel/scheduler will keep you within TIC.

---

## Coding Rules & Naming

- **VRage‑first**: use SE APIs (`IMyTextSurface`, `MySprite`, `IMyIntergridCommunicationSystem`, `MyIni`) where possible.
- **Budgets matter**: watch `Runtime.CurrentInstructionCount` (TIC) & `CurrentCallChainDepth`; **yield** early.
- **Coroutine‑first**: no `async/await`; simple `MoveNext()` state machines.
- **No GC in hot loops**: pool buffers, use bounded queues (drop oldest on overflow).
- **Branding**: use **VIOS** uppercase in **type names** (e.g., `VIOSKernel`, `IVIOSModule`); variables can be `vios`.
  Modules/components keep **neutral** names (`PowerModule`, `ScreenManagerModule`).
- **Enclosure**: all code lives inside `namespace IngameScript { partial class Program { … } }`.

More details live in `docs/architecture/VIOS-Architecture.md` and **docs/policies/VIOS-Template-Sync-Policy.md**.

---

## Docs & Architecture

- Canonical reference: `docs/architecture/VIOS-Architecture.md`
- Template policy: `docs/policies/VIOS-Template-Sync-Policy.md`

### Validate Architecture Doc (headless‑friendly)

```bash
npm i -g @mermaid-js/mermaid-cli@10
export PUPPETEER_EXECUTABLE_PATH="$(command -v chromium || command -v chromium-browser || true)"
bash tools/validate-architecture.sh
```

Expected:

```
::notice::Validated docs/architecture/VIOS-Architecture.md — N mermaid block(s) compiled successfully.
OK
```

Prefer Docker? The validator will auto‑use the Mermaid‑CLI container if present.

---

## Contributing

Pull up a chair, Engineer. We love PRs.

- Read `CONTRIBUTING.md`, `docs/policies/VIOS-Branding-Extension-Policy.md`, and `docs/policies/VIOS-Template-Sync-Policy.md`.
- Open issues with the templates under `.github/ISSUE_TEMPLATE/`.
- PRs must include the **Acceptance Checklist** (auto‑synced with the PR template).
- New modules: keep names neutral (no `VIOS` in user module **type names**), implement `IVIOSModule`.

**Template Sync in CI**

- PRs run the verifiers in **RELAXED** mode as a required check.
- Add label **`strict-template-sync`** to run the **STRICT** lane (semi‑static `.csproj` drift becomes fail), or use **Actions → Template Sync → Run workflow → `strict=true`**.

**Starter bounties**: see `codex/tasks/` (T‑001 … T‑004) for bite‑sized work items.

---

## License & Branding

- **Code:** MIT (see `LICENSE`)
- **Brands:** “Viking Industries” (VI) and **VIOS** belong to “Thorbergr” (Steam).
  Third‑party devs can build modules/components that extend VIOS without using the **VIOS** brand in their **type names**.

---

## Troubleshooting

**PB fails to compile**

- Your PB script must use:

  ```csharp
  public partial class Program : MyGridProgram
  ```

- Mixins must **not** inherit `MyGridProgram`.

**Doc validation fails**

```bash
sudo apt-get update && sudo apt-get install -y chromium || sudo apt-get install -y chromium-browser
npm i -g @mermaid-js/mermaid-cli@10
export PUPPETEER_EXECUTABLE_PATH="$(command -v chromium || command -v chromium-browser)"
bash tools/validate-architecture.sh
```

Or use Docker:

```bash
docker run --rm ghcr.io/mermaid-js/mermaid-cli:10 mmdc --version
bash tools/validate-architecture.sh
```

**MDK² Packager didn’t deploy**

- Project must be `mdk2pbscript` and include Packager/Analyzers/References.
- Build succeeded? Check the Packager output path in the logs.

---

## FAQ

**Why three PB script projects?**
To support a clean dev workflow and different coding phases:

- `VIOS.Minimal` — ultralight entrypoint for smoke tests, tiny repros, and fast CI. No extra wiring, ideal for validating core changes.
- `VIOS.Bootstrap` — production‑style wiring (kernel + core modules) that mirrors what you actually ship to a PB. Sensible Packager defaults.
- `VIOS.DevSandbox` — throwaway spikes/profiling/playground with verbose logging and experimental module toggles. Not for shipping.

**How do I make a new module?**

1. Create `Mixins/Modules/MyFeature/` (`mdk2mixin`)
2. Implement `IVIOSModule` inside `partial class Program`
3. Reference it from a PB script with `<ProjectReference/>`
4. Register it in the PB’s `Program()` (until auto‑discovery lands)

**Can I use LINQ?**
In hot paths: please don’t. Tight loops + pooled buffers win.

---

## Credits

- **Viking Industries** (VI) — “Thorbergr” (Steam) / geho (Github)
- MDK²‑SE by @malforge (package authors)

---

### Maintainer Quick Commands

```bash
# Build everything
dotnet build SE-VIOS-DevFramework.sln -c Release

# Docs check (headless)
npm i -g @mermaid-js/mermaid-cli@10
export PUPPETEER_EXECUTABLE_PATH="$(command -v chromium || command -v chromium-browser || true)"
bash tools/validate-architecture.sh
```
