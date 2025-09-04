# PR Acceptance Checklist (author must copy into PR)

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
