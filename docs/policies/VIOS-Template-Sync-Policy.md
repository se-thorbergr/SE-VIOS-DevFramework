# VIOS Template Sync Policy

**Version:** 0.2.0
**Scope:** All subprojects under `Scripts/` (PB scripts) and `Mixins/` (mixin libraries)

This policy defines the **required project shape** for MDK²-SE–based VIOS repositories and describes how our **Template Sync verifiers** evaluate compliance locally and in CI. It complements the architecture spec and CONTRIBUTING.

---

## 1) Goals & Philosophy

- Keep **PB script** and **mixin** repos consistent so they compose smoothly via MDK²’s packager.
- Offer **developer ergonomics** while preserving **strictness** where it prevents integration drift.
- Provide **fast feedback**: local scripts + CI checks print actionable hints instead of mysterious failures.

---

## 2) Project Types & Required Files

We recognize two MDK²-SE project types. Each subproject folder (direct child in `Scripts/` or `Mixins/`) must contain exactly **one** `*.csproj`.

### 2.1 PB Script projects (`mdk2pbscript`)

**Purpose:** Thin bootstraps that compile to a single SE Programmable Block script.

**Must have:**

- `Program.cs` containing **exactly**

  - `namespace IngameScript { public partial class Program : MyGridProgram { … } }`
  - Our VIOS bootstrap body (see template in `tools/templates/pbscript/Program.cs`).

- `__NAME__.mdk.ini` (renamed to `<ProjectName>.mdk.ini`) with `type=programmableblock`.
- `*.csproj` that includes:

  - `<Mdk2ProjectType>mdk2pbscript</Mdk2ProjectType>`
  - Package references: `Mal.Mdk2.PbPackager`, `Mal.Mdk2.PbAnalyzers`, `Mal.Mdk2.References`.

- Baseline repo infra: `.gitignore`, `.gitattributes`, `.editorconfig`, `Directory.Build.props`.

**May have:** additional source files, but **all** code must live inside `IngameScript.Program`.

### 2.2 Mixin projects (`mdk2mixin`)

**Purpose:** Reusable source that is merged into a PB at pack time.

**Must have:**

- At least one `*.cs` that declares `namespace IngameScript { partial class Program { … } }`.

  - **File names are free-form**; no `Program.cs` is required.
  - Our template provides `__NAME__.cs` which is scaffolded to `<ClassName>.cs`.

- `*.csproj` that includes:

  - `<Mdk2ProjectType>mdk2mixin</Mdk2ProjectType>`
  - **No** `Mal.Mdk2.PbPackager` reference.
  - Package references: `Mal.Mdk2.PbAnalyzers`, `Mal.Mdk2.References`.

- Baseline repo infra: `.gitignore`, `.gitattributes`, `.editorconfig`, `Directory.Build.props`.

**Must NOT have:** any class inheriting `MyGridProgram`.

---

## 3) Template Sync Modes

Two enforcement modes exist; both normalize line endings and ignore UTF‑8 BOMs.

- **RELAXED (default)**

  - Enforces invariants (sections 2 & 4) but **only warns** on `.csproj` drift (extra `ItemGroup`/`PropertyGroup`, added packages beyond the required set, or additional `ProjectReference`).

- **STRICT**

  - Enforces invariants **and fails** on `.csproj` drift against our templates after applying stable normalizations (strip XML comments; ignore pure `ProjectReference` groups; ignore property order).

CI runs RELAXED on all PRs. A PR labeled `strict-template-sync` (or a manual input) toggles STRICT. See workflow snippet in §7.

---

## 4) Invariants Checked

### 4.1 Common

- Exactly one `*.csproj` per subproject directory.
- Presence of baseline infra files: `.gitignore`, `.gitattributes`, `.editorconfig`, `Directory.Build.props`.
- TFM/LangVersion inherited from root `Directory.Build.props` (do not override locally).

### 4.2 PB Script (`Scripts/*`)

- `Program.cs` exists and declares `public partial class Program : MyGridProgram` **inside** `namespace IngameScript`.
- Source files must not declare any type outside `IngameScript.Program`.
- `*.mdk.ini` exists and contains `type=programmableblock`.
- `*.csproj` contains `<Mdk2ProjectType>mdk2pbscript</Mdk2ProjectType>` and the three required packages.

### 4.3 Mixin (`Mixins/*`)

- At least one source file declares `partial class Program` inside `namespace IngameScript` (no visibility/base allowed).
- No file inherits `MyGridProgram`.
- `*.csproj` contains `<Mdk2ProjectType>mdk2mixin</Mdk2ProjectType>` and **omits** the packager package.

---

## 5) Local Verifiers

Run **one** of these from repo root:

```bash
# Bash (Linux/macOS/WSL/Git Bash)
chmod +x tools/verify-templates-sync.sh
./tools/verify-templates-sync.sh                 # RELAXED (default)
MODE=STRICT ./tools/verify-templates-sync.sh     # STRICT
```

```powershell
# PowerShell 7+
pwsh ./tools/Verify-TemplatesSync.ps1            # RELAXED (default)
$env:MODE='STRICT'; pwsh ./tools/Verify-TemplatesSync.ps1
```

**Output legend**

```
===== verify-templates-sync: Summary =====
Missing files: <list>
Drift vs template: <N>
Validation issues: <M>
==========================================
```

- **Missing files** → copy from `tools/templates/<kind>/` or re‑scaffold.
- **Validation issues** → must be fixed (wrong project type; package set; enclosure rule violations; multiple `.csproj`; missing `.mdk.ini`, etc.).
- **Drift vs template** → inspect grouped diffs; acceptable in RELAXED; fails in STRICT.

---

## 6) FAQ & Edge Cases

- **Why free file names for mixins?** To mirror MDK²’s flexibility while ensuring our enclosure rule via content checks.
- **Do we enforce a file named `Program.cs` in mixins?** No.
- **Why strict packages?** Analyzer + references are required for CI parity; packager belongs only to PB scripts.
- **Line endings / BOMs?** Normalized by the verifier; keep your editor on UTF‑8 LF.

---

## 7) CI Integration

RELAXED checks run in `verify-templates-sync.yml`. To opt into STRICT automatically when a PR carries the label `strict-template-sync`, pass an environment variable consumed by the scripts.

**Workflow excerpt:**

```yaml
# .github/workflows/verify-templates-sync.yml (excerpt)
name: Template Sync
on:
  pull_request:
    types: [opened, synchronize, labeled, unlabeled, reopened]

jobs:
  verify:
    runs-on: ubuntu-latest
    env:
      MODE: ${{ contains(github.event.pull_request.labels.*.name, 'strict-template-sync') && 'STRICT' || 'RELAXED' }}
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: Verify (PowerShell)
        shell: pwsh
        run: pwsh ./tools/Verify-TemplatesSync.ps1
      - name: Verify (Bash)
        shell: bash
        run: |
          chmod +x ./tools/verify-templates-sync.sh
          ./tools/verify-templates-sync.sh
```

> The scripts default to RELAXED when `MODE` is unset; setting `MODE=STRICT` enforces strict comparison.

---

## 8) Template Sources

Templates live under `tools/templates/`:

- `tools/templates/pbscript/Program.cs` — VIOS bootstrap (C# 6 / MDK²-SE).
- `tools/templates/mixin/__NAME__.cs` — neutral primary type under `partial class Program`.
- `tools/templates/*/__NAME__.csproj` — preconfigured with the proper `<Mdk2ProjectType>` and package set.
- Standard infra files: `.gitignore`, `.gitattributes`, `.editorconfig`, `Directory.Build.props`.

---

## 9) Change Log

- **0.2.0**

  - Mixins no longer require `Program.cs`; any file may declare `partial class Program`.
  - Introduced `__NAME__.cs` + `--class` scaffolding that renames to `<ClassName>.cs` and fills `__CLASS__`.
  - Added SCAFFOLD‑STRIP blocks in templates; scaffolders remove them on copy.
  - Clarified RELAXED vs STRICT behavior and added CI label hook.

- **0.1.0**

  - Initial policy with RELAXED/STRICT modes and baseline file checks.
