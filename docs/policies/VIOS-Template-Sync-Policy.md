# VIOS Template Sync Policy (MDK² projects)

**Goal:** enforce project shape & MDK² invariants while allowing normal code evolution.

## Static files (must match templates exactly; normalized line endings)

- `.gitignore`, `.gitattributes`, `.editorconfig`, `Directory.Build.props`
- PB scripts’ `*.mdk.ini`: must contain `type=programmableblock`

**Checks:** presence required; exact match to template (LF/CRLF normalized).  
**Allowances:** whitespace/comments normalization only.

## Semi-static (schema strict; content flexible)

**`*.csproj` (exactly one per submodule):**

- **PB scripts**
  - `<Mdk2ProjectType>mdk2pbscript</Mdk2ProjectType>`
  - Require packages: `Mal.Mdk2.PbPackager`, `Mal.Mdk2.PbAnalyzers`, `Mal.Mdk2.References`
- **Mixins**
  - `<Mdk2ProjectType>mdk2mixin</Mdk2ProjectType>`
  - Forbid `Mal.Mdk2.PbPackager`
  - Require `Mal.Mdk2.PbAnalyzers`, `Mal.Mdk2.References`

**Allowed differences:** extra `ItemGroup`s/`PropertyGroup`s, `ProjectReference`s, extra packages, XML comments.  
**Diff policy:** show drift (warning) after stripping comments and `ProjectReference`-only groups; do **not** fail (unless `MODE=STRICT`).

## Flexible code

- **PB scripts:** require enclosure `public partial class Program : MyGridProgram`.
- **Mixins:** require **at least one** file declaring `partial class Program` (no visibility/base); **forbid** any `: MyGridProgram`.

No other code diffs are enforced.

## Reporting

- **Missing files** → error (fail)
- **Invariant violations** → error (fail)
- **Semi-static drift** → warning (non-blocking), unless `MODE=STRICT`

## Script toggles

- `MODE=RELAXED` (default): as above.
- `MODE=STRICT`: fail on `.csproj` drift (still with the ignore rules).
