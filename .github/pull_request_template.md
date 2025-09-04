## Summary

Describe what this PR changes. Link related issues/tasks.

## Motivation / Context

Why is this change needed? Any alternatives considered?

## Implementation Notes

Key points about design choices, performance, and MDK² specifics (PB whitelist, VRage-first usage, coroutine slicing, etc.).

## Screenshots / Logs (if applicable)

Paste relevant LCD screenshots, Echo output, or tick traces.

---

## PR Acceptance Checklist (synced with CONTRIBUTING.md)

- [ ] Builds (Windows) with .NET SDK 9 + MSBuild (Release)
- [ ] Code wrapped in `namespace IngameScript { partial class Program { ... } }`
- [ ] C# 6 only; PB whitelist-safe; VRage-first
- [ ] License header present (MIT / VIOS banner)
- [ ] **Branding:** VIOS uppercase in core types; **modules/components neutral**
- [ ] TIC/depth checks in long loops; no allocations in tick paths
- [ ] UI drawing cadence throttled (default `Update10`)
- [ ] PB→Mixin wiring via `<ProjectReference/>`; mixins are `mdk2mixin`
- [ ] Local checks run: header stamper, `tools/check-architecture.ps1`
- [ ] Docs updated if behavior/config changed (architecture/policies/README)

---

### Testing Notes

- Steps to reproduce / validate
- Expected vs. actual behavior
- Any edge cases covered

### Related Docs

- `docs/architecture/VIOS-Architecture.md`
- `docs/prompts/VIOS-Prompt-Reusable.md`
- `docs/policies/VIOS-Branding-Extension-Policy.md`
- `AGENTS.md` (Codex guide)
