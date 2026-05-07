# Changelog

All notable changes to MC Framework will be documented in this file.

## [0.1.0] — 2026-05-07

### Added — Initial release

**Documentation**
- `README.md` — humans entry point
- `AGENTS.md` — manual for AI agents (Claude Code, Copilot)
- `PROTOCOLS.md` — DEPLOY, WRAPUP, IMPORT, ROLLBACK protocols
- `docs/ARCHITECTURE.md` — Windows host ↔ WSL2 ↔ Dataverse layers
- `docs/MCP_SETUP.md` — `.mcp.json` config with WSL stdio bridge + Microsoft Learn HTTP MCP
- `docs/AUTH_HYGIENE.md` — per-client isolation principles, defense in depth
- `docs/MULTI_CLIENT.md` — onboarding guide, context switching, MDM mail template
- `docs/DATAVERSE_PATTERNS.md` — FormattedValue, OData bind, autonumber, custom APIs
- `docs/ROLLUP_PATTERNS.md` — empty-source bug + dummy-anchor pattern
- `docs/BULK_OPS_PATTERNS.md` — `az` + Web API direct, parallel batches, pagination
- `docs/IMPORT_PIPELINE.md` — RFC-4180 CSV, exceljs, header mapping, validation, preview UI

**CLI (`mc`)**
- `scripts/mc.cmd` — Windows launcher
- `scripts/mc.ps1` — PowerShell motor with commands: `new`, `adopt`, `open`, `shell`, `dev`, `deploy`, `auth status`, `logout`, `destroy`, `list`, `help`

**Bootstrap scripts**
- `scripts/new-project.ps1` — full setup of new client (WSL distro, dev tools, az/pac auth, scaffolding, templates)
- `scripts/adopt-existing.ps1` — migrate existing project to isolated model
- `scripts/distro-setup.sh` — runs inside WSL, installs Node LTS, Azure CLI, .NET SDK 8, pac CLI

**Helper templates (`scripts/lib/`)**
- `token-from-az.mjs` — `az account get-access-token` wrapper + Web API helpers
- `import-template.mjs` — parameterizable bulk import skeleton
- `reset-template.mjs` — bulk delete + rollup recalc with dummy-anchor pattern

**Templates**
- `.mcp.json.template` — Dataverse via WSL bridge + Microsoft Learn HTTP
- `CLAUDE.md.template` — thin per-project, with `@mc-framework/AGENTS.md` reference
- `.gitignore.template` — Power Platform / Code Apps defaults

### Notes

This is a documentation-and-scripts framework. There is no compiled binary.
Adoption per-project is by copying the framework folder into the project and
referencing it from `CLAUDE.md` via `@mc-framework/AGENTS.md`.
