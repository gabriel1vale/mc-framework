# Bulk Operations Patterns

Patterns for operations at scale (>100 records) on Dataverse — patterns that avoid MCP context-token stress and maximize throughput.

## When to use bulk patterns

- Bulk delete >50 records
- Bulk create >50 records
- Bulk update >50 records
- Schema exploration of many tables

## Why NOT via Dataverse MCP

`mcp__dataverse__*` tools have limitations that make bulk ops impractical:

- `read_query` cap of 20 records per call
- `create_record`/`update_record`/`delete_record` are per-record
- Each call costs ~200-300 tokens of conversation context

300 records = ~60-90K tokens just for the operation. Not sustainable.

## Pattern: `az` + Web API direct

The Dataverse Web API allows direct POST/PATCH/DELETE. Auth via Bearer token, which `az` can issue.

### Token setup

Inside the WSL distro:

```bash
DV_TOKEN=$(az account get-access-token --resource <env-url> --query accessToken -o tsv)
```

Where `<env-url>` is the env URL without `/api/data/...` (e.g. `https://example.crm4.dynamics.com/`).

The token is JWT, typically expires in 1h. For long operations, refresh inside the script (re-call `az account get-access-token`).

### Node.js script structure

```javascript
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ENV_URL  = '<env-url>';
const API_BASE = `${ENV_URL}/api/data/v9.2`;

const token = process.env.DV_TOKEN;
if (!token) {
  console.error('ERROR: DV_TOKEN required.');
  console.error('Run: $env:DV_TOKEN = (az account get-access-token --resource <env-url> --query accessToken -o tsv)');
  process.exit(1);
}

const headers = {
  Authorization: `Bearer ${token}`,
  Accept: 'application/json',
  'OData-MaxVersion': '4.0',
  'OData-Version': '4.0',
  'Content-Type': 'application/json',
  Prefer: 'return=representation',
};

async function dvGet(pathRel) {
  const r = await fetch(`${API_BASE}${pathRel}`, { headers });
  if (!r.ok) throw new Error(`GET ${pathRel} → ${r.status} ${await r.text()}`);
  return r.json();
}

async function dvGetAll(pathRel) {
  const out = [];
  let url = `${API_BASE}${pathRel}`;
  while (url) {
    const r = await fetch(url, { headers: { ...headers, Prefer: 'odata.maxpagesize=5000' } });
    if (!r.ok) throw new Error(`GET ${url} → ${r.status} ${await r.text()}`);
    const j = await r.json();
    out.push(...(j.value ?? []));
    url = j['@odata.nextLink'] ?? null;
  }
  return out;
}

async function dvPost(pathRel, body) {
  const r = await fetch(`${API_BASE}${pathRel}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`POST ${pathRel} → ${r.status} ${await r.text()}`);
  return r.json();
}

async function dvDelete(pathRel) {
  const r = await fetch(`${API_BASE}${pathRel}`, { method: 'DELETE', headers });
  if (!r.ok && r.status !== 404) throw new Error(`DELETE ${pathRel} → ${r.status} ${await r.text()}`);
}

function chunk(arr, n) {
  const out = [];
  for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n));
  return out;
}
```

(There is a complete helper at `scripts/lib/token-from-az.mjs`.)

### Bulk delete

```javascript
const ids = (await dvGetAll(`/<entitysetname>?$select=<idfield>`)).map(r => r['<idfield>']);
let deleted = 0;
for (const batch of chunk(ids, 10)) {
  await Promise.all(batch.map(id => dvDelete(`/<entitysetname>(${id})`)));
  deleted += batch.length;
  process.stdout.write(`deleted ${deleted}/${ids.length}\r`);
}
```

### Bulk create

```javascript
let created = 0;
const errors = [];
for (const batch of chunk(records, 10)) {
  const results = await Promise.allSettled(
    batch.map(r => dvPost(`/<entitysetname>`, buildPayload(r))),
  );
  results.forEach((res, i) => {
    if (res.status === 'fulfilled') created++;
    else errors.push(`row ${batch[i].rowNumber}: ${res.reason.message}`);
  });
  process.stdout.write(`created ${created}/${records.length}\r`);
}
```

### Batch size

10 parallel is the sweet spot in most environments. More than that and you start seeing 429 (Too Many Requests) or 5xx from Dataverse. For large/slow tables, drop to 5.

## Pattern: invoke Custom APIs / Functions

For `CalculateRollupField` or `WhoAmI` or other unbound APIs:

```javascript
const target = JSON.stringify({ '@odata.id': `<entitysetname>(${parentId})` });
const url = `${API_BASE}/CalculateRollupField(Target=@T,FieldName=@F)?@T=${encodeURIComponent(target)}&@F='${columnName}'`;
const r = await fetch(url, { headers });
```

(GET method for functions; POST for actions with body.)

## Pattern: pagination

Web API by default returns 5000 records per page, with `@odata.nextLink` if there are more:

```javascript
async function dvGetAll(pathRel) {
  const out = [];
  let url = `${API_BASE}${pathRel}`;
  while (url) {
    const r = await fetch(url, { headers: { ...headers, Prefer: 'odata.maxpagesize=5000' } });
    if (!r.ok) throw new Error(...);
    const j = await r.json();
    out.push(...(j.value ?? []));
    url = j['@odata.nextLink'] ?? null;
  }
  return out;
}
```

`Prefer: odata.maxpagesize=5000` is the cap. More than 5000 doesn't return more; you need to paginate.

## Pattern: server-side filtering

Instead of loading everything and filtering in memory, use `$filter`:

```javascript
const result = await dvGetAll(
  `/crd1_orderlines?$filter=crd1_type eq 100000001 and crd1_quantity gt 0&$select=crd1_seqid,crd1_quantity`
);
```

OData operators: `eq`, `ne`, `gt`, `lt`, `ge`, `le`, `and`, `or`, `not`, `contains(field,'text')`, `startswith(field,'text')`.

## Bulk schema discovery

To map the schema of many tables:

```javascript
const tables = await dvGetAll(`/EntityDefinitions?$select=LogicalName,DisplayName&$filter=IsCustomEntity eq true`);
for (const t of tables) {
  const cols = await dvGetAll(`/EntityDefinitions(LogicalName='${t.LogicalName}')/Attributes?$select=LogicalName,AttributeType`);
  // ... process
}
```

Useful to generate schema docs or to generate import mapping configs.

## Performance considerations

- **Parallel of 10**: sweet spot. >10 starts hitting 429.
- **Batch operations endpoint**: Dataverse has `$batch` for atomic multi-op. More complex to implement; only worth it for cases where transactionality is essential.
- **Sleep between batches**: for very large operations (>5000), `await new Promise(r => setTimeout(r, 100))` between batches eases throttling.

## Token expiration mid-operation

For operations that may take >50min (close to token TTL):

```javascript
async function getToken() {
  const { execSync } = await import('node:child_process');
  return execSync(`az account get-access-token --resource ${ENV_URL} --query accessToken -o tsv`, { encoding: 'utf8' }).trim();
}

let token = await getToken();
let lastRefresh = Date.now();
const REFRESH_INTERVAL = 45 * 60 * 1000; // 45min

async function call(...args) {
  if (Date.now() - lastRefresh > REFRESH_INTERVAL) {
    token = await getToken();
    lastRefresh = Date.now();
  }
  // use token...
}
```

## Anti-patterns

### ❌ Bulk ops via Dataverse MCP

300+ tool calls = context destroyed. For any op >50 records, write a script.

### ❌ Sequential bulk

`for (const r of records) await create(r)` instead of `Promise.all` in batches. 100x slower.

### ❌ No `Promise.allSettled`

`Promise.all` aborts on the first error. For bulk imports where you want to process everything and report errors at the end, always `Promise.allSettled`.

### ❌ Forgetting `OData-Version` header

Without `OData-Version: 4.0`, Dataverse may return v3 OData format or errors. Always include.

### ❌ Hardcoding sequential ID without getNextId()

If the table already has records with high IDs in other zones (not top 100 most recent), risk of collision. `getNextId()` should paginate everything (see `DATAVERSE_PATTERNS.md`).

## Where to put bulk scripts

Convention: per project, in `<project>/dataverse/scripts/`. Each script standalone, with its own `package.json` if it needs external deps (e.g. `exceljs`).

The framework provides templates in `scripts/lib/` you copy and adapt:

- `import-template.mjs` — bulk import skeleton
- `reset-template.mjs` — bulk delete + recalc skeleton
- `token-from-az.mjs` — auth helper
