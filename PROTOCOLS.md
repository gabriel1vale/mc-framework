# PROTOCOLS

Operational protocols consistent across clients. When the user invokes one of these keywords, follow the steps described exactly.

---

## DEPLOY

Deploy a Code App to a Dataverse solution.

### Preconditions

- Code App scaffolded in a folder containing `power.config.json`
- `pac` auth active **inside the client's WSL distro** (verify with `wsl -d <Distro> -- pac auth list`)
- `git status` clean (recommended, not required)

### Steps

#### 1. Pre-validation (no confirmation; failure blocks)

```bash
wsl -d <Distro> --cd <project-wsl-path> -- bash -lc "npx tsc -b --noEmit"
wsl -d <Distro> --cd <project-wsl-path> -- bash -lc "npm run build"
wsl -d <Distro> -- pac auth list
```

Failure of any of these → report and stop. **Do not deploy.**

#### 2. Explicit confirmation

Show the user:
- App name (from `power.config.json`)
- Solution name
- Env URL
- Size of `dist/`

Ask `y/n`. Cancel if not.

#### 3. Push

```bash
wsl -d <Distro> --cd <project-wsl-path> -- bash -lc "pac code push --solutionName <Solution>"
```

Capture the play URL returned. On error → report and stop.

#### 4. Post-deploy verification

```bash
wsl -d <Distro> -- pac code list
```

Confirm the app appears with `appId` populated. Compare with `power.config.json` (on first deploy, the appId is written back automatically).

#### 5. Update logs

- `dataverse/logs/YYYY-MM-DD/session.md` (or project equivalent) — append "Deploy completed" entry with version, play URL, solution + env IDs, brief list of commits since last deploy
- `SESSION_HANDOFF.md` if there are relevant changes
- `VERSION_HISTORY.md` with the new release entry (mark the previous as `COMPLETE - DO NOT MODIFY`)
- Bump version in project's `CLAUDE.md`

#### 6. Git tag (optional)

Ask the user if they want to create tag `v<X>-deploy-<env>` on the current commit. NOT auto-pushed.

#### 7. Report completion

Final URL, deployed version, next steps (test via URL, verify permissions in the solution).

### Failure modes

- `--solutionName` rejected → solution doesn't exist or user lacks permission. Report and suggest verifying in maker.
- `pac auth` expired → re-authenticate with `wsl -d <Distro> -- pac auth create --deviceCode --environment <env-id>`, then retry.
- Build fails → show TS/Vite errors, **do not attempt auto-fix without approval**.
- Push timeout → do not auto-retry; report for the user to decide.

---

## WRAPUP

End-of-session / release preparation.

### 1. Codebase cleanup

- Review files created/modified in the session
- Delete temporary files (`*.tmp`, experimental code, debug `console.log`)
- Check for unused imports, dead code
- Confirm no credential files (`.env`, etc.) are being committed

### 2. Build verification

```bash
wsl -d <Distro> --cd <project-wsl-path> -- bash -lc "npm run build"
```

On failure → stop and investigate.

### 3. Documentation update

- Bump version in `CLAUDE.md` (header)
- Append entry to `VERSION_HISTORY.md` with:
  - Version and title
  - Release overview
  - Files modified
  - Lessons learned (reference to SESSION_HANDOFF)
  - Status: `COMPLETE - DO NOT MODIFY`
- Update `SESSION_HANDOFF.md` with:
  - Current status (version, last log)
  - Session summary
  - Next priorities

### 4. Lessons capture

If the user corrected a decision of yours during the session, propose a "Lesson" for `SESSION_HANDOFF.md`:

```markdown
### L<N> — <Short title>
**Rule:** <actionable rule>
**Why:** <concrete reason — constraint, incident, strong preference>
**How to apply:** <when/where>
```

Show to the user for approval before writing.

### 5. Git commit

Configure git locally if needed (not global):
```bash
git config user.name "<name>"
git config user.email "<email>"
```

Confirm target branch with the user. `git status`. Stage with **explicit paths** (NOT `git add -A` in projects with credential risk). Commit with format:

```
feat: <short description> (v<version>)

- <change 1>
- <change 2>

Co-Authored-By: Claude <noreply@anthropic.com>
```

### 6. Push (only with confirmation)

Ask the user before `git push`. NOT auto-push even if the session started with "wrapup".

---

## IMPORT

Bulk import of data from a file (xlsx/csv) into a Dataverse table.

### 1. Gather info

- Source file path
- Target table
- Column mapping → fields (can ask the user or infer from header)
- Edit mode (import as adjustment — `<edit_field> = true`) or real movement

### 2. Inspect schema

```
mcp__dataverse__describe_table(<table>)
```

Identify:
- Lookup fields (need `@odata.bind`)
- Required fields
- Choice fields (need option set values)
- Boolean fields (especially "is edit" / "is adjustment" flag if present)

### 3. Pre-resolve lookups

For each lookup:
- Load index of the related table (e.g., products by SKU)
- Build in-memory map

### 4. Parse + validate

- Robust parser (RFC-4180 for CSV, exceljs for xlsx)
- Per-row validation: required fields, lookup matches, value types
- Invalid rows go to one bucket, valid to another
- Report summary to the user before submitting

### 5. Confirmation

If ≥ 100 valid rows, **force explicit confirmation** (`window.confirm` if UI, y/n prompt if script).

### 6. Bulk create

Pattern: `Promise.allSettled` in batches of 10.

For auth: `az account get-access-token --resource <env-url>` from **inside the distro**.

```javascript
const token = process.env.DV_TOKEN;
const headers = {
  Authorization: `Bearer ${token}`,
  'OData-Version': '4.0',
  'Content-Type': 'application/json',
  Prefer: 'return=representation',
};

for (const batch of chunk(rows, 10)) {
  const results = await Promise.allSettled(
    batch.map((r) => fetch(`${API_BASE}/<entitysetname>`, {
      method: 'POST',
      headers,
      body: JSON.stringify(buildPayload(r)),
    })),
  );
  // tally success/failure
}
```

### 7. Recalc rollups

If the table feeds rollup columns in another table, follow `docs/ROLLUP_PATTERNS.md`. **Don't assume the engine recalcs on its own** — there's a known empty-source bug (see doc).

### 8. Verify + report

Count records via `read_query`. Report totals to the user. Update `dataverse/logs/YYYY-MM-DD/session.md` with:
- Source file
- Metrics (matched/skipped/created/errors)
- List of skipped (if applicable)

---

## ROLLBACK

Revert a failed deploy or commit.

### 1. Identify last known good

- `git log --oneline -10`
- Compare with `VERSION_HISTORY.md`
- Ask the user which version is the "good state"

### 2. Confirm with user

**Destructive operation.** Explicit y/n confirmation.

### 3. Execute

To revert code (preference: new commit that reverts, NOT reset --hard):

```bash
git revert <commit-sha>
```

For extreme cases (commit not yet published, working tree clean):

```bash
git reset --hard <good-sha>
```

To revert a deploy (re-deploy previous version):

1. `git checkout <previous-version-tag>`
2. Build in the distro
3. `pac code push --solutionName <Solution>` (same DEPLOY pattern)

### 4. Verify

- Application still builds
- Application still runs
- Critical features tested (manual, or via E2E tests if present)

### 5. Document

`dataverse/logs/YYYY-MM-DD/session.md`:
- Reason for rollback
- Reverted version + "good" version
- Steps taken
- Lessons (in SESSION_HANDOFF if applicable)
