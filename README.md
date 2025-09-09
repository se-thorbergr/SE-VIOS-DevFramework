# SE-VIOS-DevFramework

[![CI — Build & Policy Gates](https://github.com/se-thorbergr/SE-VIOS-DevFramework/actions/workflows/ci.yml/badge.svg)](https://github.com/se-thorbergr/SE-VIOS-DevFramework/actions/workflows/ci.yml)
[![Template Sync](https://github.com/se-thorbergr/SE-VIOS-DevFramework/actions/workflows/verify-templates-sync.yml/badge.svg)](https://github.com/se-thorbergr/SE-VIOS-DevFramework/actions/workflows/verify-templates-sync.yml)
[![Docs Validate](https://github.com/se-thorbergr/SE-VIOS-DevFramework/actions/workflows/docs-validate.yml/badge.svg)](https://github.com/se-thorbergr/SE-VIOS-DevFramework/actions/workflows/docs-validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> **Space Engineers VIOS Development Framework** — modular, policy-driven scripting environment for in-game automation.

---

## 🚀 Overview

SE-VIOS-DevFramework is the **super-repo** that orchestrates the VIOS ecosystem:

- Provides **global policies** (Template Sync, docs, CI/CD).
- Manages **core mixins** and **starter scripts**.
- Hosts shared tooling (scaffolders, verifiers).

It is designed for:

- **Reliability** — enforced sync policies and CI gates.
- **Extensibility** — mixin-based architecture for modules.
- **Developer experience** — scaffolding, strict/relaxed modes, ready-to-deploy samples.

---

## 📦 Repo Structure

```text
SE-VIOS-DevFramework/
├── Scripts/
│   ├── VIOS.Bootstrap   → Starter script entrypoint
│   ├── VIOS.DevSandbox  → Dev playground for rapid testing
│   └── VIOS.Minimal     → Lean starter template
├── Mixins/
│   ├── VIOS.Core        → Core runtime mixin set
│   └── Modules/
│       ├── Power        → Power management module
│       └── ScreenMgr    → LCD/breadcrumb manager
├── Components/          → Optional shared components
├── tools/               → Scaffolders & verifiers
├── docs/                → Policies, architecture, contributing guides
└── .github/workflows/   → CI (Template Sync, docs validate, etc.)
```

---

## ⚙️ Development Workflow

1. **Clone with submodules:**

   ```bash
   git clone https://github.com/se-thorbergr/SE-VIOS-DevFramework.git
   cd SE-VIOS-DevFramework
   git submodule update --init --recursive
   ```

2. **Scaffold a submodule (example: mixin):**

   ```bash
   tools/scaffold-submodule.sh mixin --class MyModule
   ```

3. **Verify template sync (RELAXED by default):**

   ```bash
   tools/verify-templates-sync.sh
   ```

   Add label `strict-template-sync` to enforce **STRICT** mode in CI.

4. **Open in Space Engineers** using MDK² build.

---

## ✅ CI & Policy

- **Required check:** `Template Sync (gate)` (branch protection)
- **STRICT trigger:** `strict-template-sync` label
- Verifiers:

  - Bash → `tools/verify-templates-sync.sh`
  - PowerShell → `tools/Verify-TemplatesSync.ps1`

- Scaffolders:

  - Bash → `tools/scaffold-submodule.sh`
  - PowerShell → `tools/Scaffold-Submodule.ps1`

See [docs/policies/VIOS-Template-Sync-Policy.md](docs/policies/VIOS-Template-Sync-Policy.md).

---

## 📖 Documentation

- [Architecture](docs/architecture/VIOS-Architecture.md)
- [Template Sync Policy](docs/policies/VIOS-Template-Sync-Policy.md)
- [CONTRIBUTING](CONTRIBUTING.md)
- [AGENTS.md](AGENTS.md)

---

## 🛠 Status

- **WIP:** polishing docs (README quickstart, AGENTS.md, badges)
- **Backlog:** module demos (ScreenMgr + Power), starter modules (Airlock, Cargo, Production)

---

## 🙌 Credits

- Core framework: **Thorbergr**
- Contributions & fixes: **geho**, **community contributors**

---

## 📜 License

MIT — see [LICENSE](LICENSE).
