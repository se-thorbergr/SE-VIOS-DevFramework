# VIOS Branding & Extension Policy v1.0

This document defines how the **Viking Industries** (VI) and **Viking Industries Operating System** (VIOS) brands appear in code, class names, UI strings, and module ecosystems—while enabling third parties to build compatible modules and even alternative kernels **without** using the VIOS brand in their own class names.

---

## 1) Brand Definitions

- **Viking Industries (VI)** — the fictional company and publisher of the framework.
- **Viking Industries Operating System (VIOS)** — the in‑game OS and core framework for SE PBs, developed by VI.
- Brands belong to **CEO “Thorbergr”** (Steam avatar) as creator/founder.

---

## 2) Naming Conventions

### 2.1 Core Components (maintained by VI)

- **Rule:** Any _core_ class/interface/struct that is part of the official framework must use **uppercase `VIOS`** in the type name.

  - Examples: `VIOSKernel`, `IVIOSModule`, `VIOSContext`, `VIOSPacket`, `VIOSMessageRouter`, `VIOSModuleBase`, `VIOSConsole`.

- File and folder names inside the official Mixins should also reflect this (e.g., `Mixins/VIOS/VIOS.cs`).

### 2.2 Third‑Party Extensions (community modules)

- Third‑party **class names must not be required** to include the brand.

  - Allowed examples: `PowerModule`, `AcmeAirlockModule`, `ScreenManagerPlus`.
  - Also allowed if authors want to show compatibility: `PoweredByVIOS` in docs/readme, **not** in class names.

- **Interfaces** used to achieve compatibility may contain the brand (e.g., `IVIOSModule`), but implementers are free to name their **classes** however they like.

### 2.3 Variables & Fields

- Variables/fields may use lowercase `vios`, e.g., `var viosKernel = new VIOSKernel();`.

---

## 3) Namespace & Package Conventions

- **Reserved (core):** `IngameScript.VIOS.*` (source-merged under `IngameScript` → `partial class Program`).
- **Third‑party modules:** use neutral or vendor‑prefixed naming in code comments and docstrings, e.g., `Acme.PowerModule`, though within SE scripts all types live inside `IngameScript.Program`.
- **Module IDs** (strings used in registry/CustomData): `vendor.module` format preferred, e.g., `vi.power`, `acme.airlockplus`.

---

## 4) Protocol & Tagging

- Default IGC tag **`VIOS`** identifies the wire protocol. It is **not** a requirement to put brand in your class names to use the tag.
- Third parties may:

  1. Use the `VIOS` tag to interoperate directly, or
  2. Change `Network.Tag` in `CustomData` to a non‑branded value for private networks.

- **Name Service** registry keys default to `VIOS` prefix but are configurable.

```ini
[VIOS]
Network.Tag=VIOS    ; third parties may set AcmeNet or similar
```

---

## 5) Licensing & Trademarks (MIT — confirmed)

- **Code License:** **MIT** for all core **VI/VIOS** code published by Viking Industries / Thorbergr.
- **Third-party usage:** Forks, extensions, and alternative kernels may adopt any MIT‑compatible license; attribution as per MIT terms.
- **Trademark/Brand Policy:** keep a simple `TRADEMARK.md` stating:

  - The names **“Viking Industries”**, **“Viking Industries Operating System”**, and **“VIOS”** identify the original project.
  - Third parties can build compatible modules/kernels **without** using these names in their class names or product branding.
  - "Compatible with VIOS" and "Powered by VIOS" badges may be used as described in Section 6.

---

## 6) Compatibility Badges (textual)

- `Compatible with VIOS` — for modules implementing `IVIOSModule` semantics and passing handshake checks.
- `Powered by VIOS` — for deployments running the official `VIOSKernel`.

---

## 7) API Boundaries That Enable Unbranded Extensibility

### 7.1 Stable Interfaces (brand appears only in interface names)

- `IVIOSModule`, `IVIOSKernel`, `VIOSContext`, `VIOSPacket` are the main “contract” types.
- Third‑party classes can be neutral:

```csharp
namespace IngameScript
{
  partial class Program
  {
    class PowerModule : IVIOSModule
    {
      public string Name { get { return "PowerModule"; } }
      public void Init(VIOSContext ctx, IModuleRegistrar reg) { }
      public void Start(VIOSContext ctx) { }
      public void Tick(VIOSContext ctx) { }
      public void Stop(VIOSContext ctx) { }
      public void OnMessage(ref VIOSPacket p, VIOSContext ctx) { }
      public void DescribeStatus(StringBuilder sb) { }
    }
  }
}
```

### 7.2 Optional Base Class

- The official base class is branded: `VIOSModuleBase` (for convenience, pooling hooks, metrics). Using it is optional.

```csharp
abstract class VIOSModuleBase : IVIOSModule
{
  public abstract string Name { get; }
  public virtual void Init(VIOSContext ctx, IModuleRegistrar reg) { }
  public virtual void Start(VIOSContext ctx) { }
  public virtual void Tick(VIOSContext ctx) { }
  public virtual void Stop(VIOSContext ctx) { }
  public virtual void OnMessage(ref VIOSPacket p, VIOSContext ctx) { }
  public virtual void DescribeStatus(StringBuilder sb) { }
}

// Third party may choose either path:
class AcmeAirlockModule : VIOSModuleBase { public override string Name { get { return "Acme.Airlock"; } } }
class ScreenManagerPlus : IVIOSModule { public string Name { get { return "Screen.Plus"; } } /* implement members */ }
```

---

## 8) UI, Strings, and Headers

- **Core** screens may show the brand in headers/footers (e.g., `VIOS vX.Y | Viking Industries`).
- **Third‑party** modules should avoid using VIOS brand in end‑user strings unless indicating compatibility, e.g., `Compatible with VIOS`.

---

## 9) File Headers (core only)

```csharp
/*
  Viking Industries Operating System (VIOS)
  (c) Thorbergr — Viking Industries
  License: MIT — see LICENSE
  Trademark: VI / VIOS names are used to identify the original project.
*/
```

---

## 10) CustomData & Discovery Conventions

- **Module Registration Key:** Modules list themselves by `vendor.module`.
- **Brand‑neutral examples:**

```ini
[Modules]
Enable=vi.power,acme.airlockplus,screen.plus

[Network]
Tag=VIOS      ; default for shared interop; can be changed
```

---

## 11) Alternative Kernels (Unbranded Implementations)

- Third parties may implement `IVIOSKernel` with a neutral class name:

```csharp
class OpenKernel : IVIOSKernel
{
  public void Init(IEnv env, IConfig cfg) { }
  public void RegisterModule(IVIOSModule module) { }
  public void Start(UpdateFrequency freq) { }
  public void Tick(UpdateType type, string argument) { }
  public void Save() { }
}
```

- They can still interoperate with VIOS modules via the shared interfaces and the IGC protocol tag.

---

## 12) Enforcement & CI Checks (core repo)

- Lint rule: **Types containing the OS name must use uppercase `VIOS`**.
- Lint rule: Disallow `VIOS` prefix in third‑party example modules (samples show neutral names).
- CI test: Wire‑protocol handshake across different `Network.Tag` values.

---

## 13) Quick Checklist

- [x] Core types/classes use uppercase **VIOS**.
- [x] Third‑party classes are free to choose neutral names.
- [x] Interfaces remain branded (`IVIOS*`) to define stable contracts.
- [x] IGC tag default `VIOS` but configurable.
- [x] License + TRADEMARK notes keep brand while enabling open extensions.

---

## Appendix B: LICENSE (MIT)

```
MIT License

Copyright (c) 2025 geho / Thorbergr

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Appendix C: TRADEMARK.md (template)

```
Viking Industries (VI) and Viking Industries Operating System (VIOS) are names
used to identify the original project by geho / Thorbergr. The code is licensed
under MIT (see LICENSE). You may build compatible modules and kernels without
using these names in your class names or product branding. You may use the
phrases "Compatible with VIOS" or "Powered by VIOS" when the conditions in the
Branding & Extension Policy are met.
```

---

## Appendix D: NOTICE (optional)

```
This distribution includes the VI/VIOS core under the MIT License.
Copyright (c) 2025 geho / Thorbergr.
See LICENSE for details.
```
