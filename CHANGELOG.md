# Changelog

All notable changes to MC Framework will be documented in this file.

## [0.1.0] — 2026-05-07

### Added — Initial release

**Scope:** strictly authentication, access, and environment provisioning for multi-client Power Platform consulting on personal hardware.

What is intentionally **out of scope**: development workflows (deploy, build, scaffolding), domain patterns (Dataverse lookups, rollups, imports), and project conventions (version history, session logs). Those are sourced from Microsoft Learn (via MCP), the official Microsoft repos ([`microsoft/PowerAppsCodeApps`](https://github.com/microsoft/PowerAppsCodeApps), [`microsoft/power-platform-skills`](https://github.com/microsoft/power-platform-skills)), the project's own `CLAUDE.md`, and the AI agent's general reasoning.

**Documentation**
- `README.md` — entry point (PT-BR)
- `AGENTS.md` — manual for AI agents (Claude Code, Copilot) — what's in scope, what's out, and where to look for the rest
- `docs/ARCHITECTURE.md` — Windows host ↔ WSL2 ↔ Dataverse layers
- `docs/MCP_SETUP.md` — `.mcp.json` config with WSL stdio bridge + Microsoft Learn HTTP MCP
- `docs/AUTH_HYGIENE.md` — per-client isolation principles, defense in depth
- `docs/MULTI_CLIENT.md` — onboarding guide, context switching, MDM mail template

**CLI (`mc`)**
- `scripts/mc.cmd` — Windows launcher
- `scripts/mc.ps1` — PowerShell motor with commands: `new`, `adopt`, `open`, `shell`, `dev`, `auth status`, `logout`, `destroy`, `list`, `help`

**Bootstrap scripts**
- `scripts/new-project.ps1` — provision new client environment (WSL distro, dev tools, az/pac auth, templates)
- `scripts/adopt-existing.ps1` — provision env for an existing project
- `scripts/distro-setup.sh` — runs inside WSL, installs Node LTS, Azure CLI, .NET SDK 8, pac CLI

**Templates**
- `.mcp.json.template` — Dataverse via WSL bridge + Microsoft Learn HTTP
- `CLAUDE.md.template` — thin per-project, with `@mc-framework/AGENTS.md` reference, redirects dev questions to Microsoft Learn / Microsoft repos / the agent
- `.gitignore.template` — sensible defaults

### Notes

This is a documentation-and-scripts framework. There is no compiled binary.
Adoption per-project is by copying the framework folder into the project and
referencing it from `CLAUDE.md` via `@mc-framework/AGENTS.md`.

The framework's job is to get you into an isolated, properly-authenticated
WSL environment. Once there, what you build is up to you (and the agent),
guided by Microsoft's official sources.
