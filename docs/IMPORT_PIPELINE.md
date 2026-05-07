# Import Pipeline

Pattern for implementing data import (xlsx/csv) into Dataverse tables, inside a Code App or via standalone script.

## When to use inside Code App vs external script

| Situation | Where |
|---|---|
| End user does manual upload via UI | Inside Code App (browser, exceljs lazy-loaded) |
| Initial / ad-hoc / migration bulk import | Standalone script (`dataverse/scripts/`) with `az` + Web API |
| Recurring automated import | Power Automate flow OR scheduled standalone script |

The difference is only scale/audience. The **validation flow** is the same.

## Pipeline structure (5 phases)

### Phase 1: Parse

Convert source file into typed rows.

**CSV** — implement an RFC-4180 parser (do not use simple `split(',')`, fails on fields with embedded commas):

```javascript
function parseCsv(text) {
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);  // strip BOM
  const records = [];
  let row = [], field = '', inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; }
        else inQuotes = false;
      } else field += ch;
    } else {
      if (ch === '"' && field === '') inQuotes = true;
      else if (ch === ',') { row.push(field); field = ''; }
      else if (ch === '\r') {
        if (text[i + 1] === '\n') i++;
        row.push(field); field = '';
        records.push(row); row = [];
      } else if (ch === '\n') {
        row.push(field); field = '';
        records.push(row); row = [];
      } else field += ch;
    }
  }
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    records.push(row);
  }
  return records.map(r => r.map(c => c.trim()));
}
```

Supports:
- Quoted fields with embedded commas
- Escaped quotes (`""`)
- Newlines inside quoted fields
- BOM at start

**Excel (xlsx)** — use `exceljs`:

```javascript
import ExcelJS from 'exceljs';

const wb = new ExcelJS.Workbook();
await wb.xlsx.load(buffer);
const sheet = wb.worksheets[0];

const headerRow = sheet.getRow(1);
const headers = [];
for (let c = 1; c <= sheet.columnCount; c++) {
  headers.push(String(headerRow.getCell(c).value ?? '').trim());
}

const rows = [];
for (let r = 2; r <= sheet.rowCount; r++) {
  const cells = [];
  for (let c = 1; c <= sheet.columnCount; c++) {
    const v = sheet.getRow(r).getCell(c).value;
    cells.push(v === null || v === undefined ? '' : String(v));
  }
  if (cells.every(c => c.trim() === '')) continue;  // skip empty rows
  rows.push(cells);
}
```

For bundle size, use dynamic `import('exceljs')` in UI (lazy-load only when the user does an import).

### Phase 2: Header mapping

Flexible header → canonical field map, tolerant to case/accent/spacing variations:

```javascript
function normalizeHeader(s) {
  return s.toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')  // strip diacritics
    .replace(/\s+/g, ' ')
    .trim();
}

const expected = {
  'sku': 'SKU',
  'reference': 'SKU',
  'product': 'SKU',
  'account': 'Account',
  'region': 'Region',
  'type': 'Type',
  'quantity': 'Quantity',
  'qty': 'Quantity',
};

function buildHeaderMap(cells) {
  const map = {};
  for (let i = 0; i < cells.length; i++) {
    const norm = normalizeHeader(cells[i]);
    const canonical = expected[norm];
    if (canonical && !(canonical in map)) map[canonical] = i;
  }
  // Validate required headers present
  return map;
}
```

### Phase 3: Pre-resolve lookups

Before validating rows, load lookups in memory — index by human key (reference, name, etc.) → guid.

```javascript
const productByRef = new Map();
const result = await dvGetAll('/crd1_products?$select=crd1_productid,crd1_sku,crd1_name');
for (const p of result) {
  if (p.crd1_sku) {
    productByRef.set(p.crd1_sku.trim(), { id: p.crd1_productid, name: p.crd1_name });
  }
}

// For accounts, only lookup the unique names referenced in the import
const uniqueAccountNames = [...new Set(rows.map(r => r.accountName).filter(Boolean))];
const accountByName = new Map();
for (const name of uniqueAccountNames) {
  const escaped = name.replace(/'/g, "''");
  const result = await dvGet(`/accounts?$select=accountid,name&$filter=name eq '${escaped}'&$top=5`);
  if (result.value.length === 1) {
    accountByName.set(normalizeName(name), { id: result.value[0].accountid, name: result.value[0].name });
  }
  // Ambiguous (>1) or not-found (0) → row goes to invalid
}
```

### Phase 4: Per-row validation

For each row, validate required fields, resolved lookups, correct value types. Separate into `valid` vs `invalid`.

```javascript
const valid = [];
const invalid = [];

for (const r of rows) {
  const errors = [];
  const refKey = r.sku.trim();
  const product = refKey ? productByRef.get(refKey) : undefined;
  if (!refKey) errors.push('SKU missing');
  else if (!product) errors.push(`SKU "${refKey}" not found`);

  // ... other validations

  if (errors.length > 0) {
    invalid.push({ rowNumber: r.rowNumber, raw: r, errors });
  } else {
    valid.push({ rowNumber: r.rowNumber, productId: product.id, /* ... resolved fields */ });
  }
}
```

### Phase 5: Preview + commit

Before writing, show summary to the user:

```
Total: 169 rows analyzed
Valid: 162
Invalid: 7

Confirm import of the 162 valid? (y/n)
```

If ≥ 100 rows, **force explicit confirmation** (in UI: `window.confirm`; in script: y/n prompt).

Commit in parallel (batches of 10 with `Promise.allSettled` — see `BULK_OPS_PATTERNS.md`).

## UI in Code App

```typescript
// ImportRecords.tsx (or generic)

type Phase = 'idle' | 'parsing' | 'preview' | 'submitting' | 'done';

const [phase, setPhase] = useState<Phase>('idle');
const [parseResult, setParseResult] = useState<ParseResult | null>(null);

async function handleFile(file: File) {
  setPhase('parsing');
  try {
    const ext = file.name.toLowerCase();
    let raw;
    if (ext.endsWith('.csv')) raw = parseCsvFile(await file.text());
    else if (ext.endsWith('.xlsx')) raw = await parseExcelFile(file);
    else throw new Error('Unsupported format');

    const result = await resolveAndValidate(raw);
    setParseResult(result);
    setPhase('preview');
  } catch (err) {
    // ...
  }
}

async function handleConfirm() {
  if (parseResult.valid.length >= 100) {
    if (!window.confirm(`Will create ${parseResult.valid.length} records. Continue?`)) return;
  }
  setPhase('submitting');
  const result = await commitImport(parseResult.valid);
  // ...
}
```

Preview modal with 2 tables: valid (with confirm button) + invalid (with error messages).

## Templates

The framework provides:

- `templates/import-template.csv` — header + 3 example rows
- `templates/import-template.xlsx` — sheet "Data" + sheet "Instructions"

The app generates these for download via `lib/templates.ts` (parameterizable per schema).

## Imports as adjustments (edit mode)

Pattern: bulk imports should be marked as adjustments (not confused with real records inserted manually). Typical convention:

- If the schema has a boolean column like `is_edit_mode` / `is_adjustment` / `crd1_isadjustment` → set `true` for all bulk import records
- If not, create the column, OR use timestamp/source field to distinguish

Reason: audit, selective undo, UI filters ("show only adjustments vs real records").

## Recalc rollups afterwards

If the imported table feeds rollup columns, follow `ROLLUP_PATTERNS.md` to force recalc. **Don't wait** for the natural rollup job.

## Common gotchas

### Excel dates as numbers

Excel stores dates as float numbers (days since 1900). exceljs converts to `Date` automatically, but if the cell is formatted as a number, it comes as `number`. Always check:

```javascript
const v = cell.value;
const date = v instanceof Date ? v : (typeof v === 'number' ? new Date((v - 25569) * 86400 * 1000) : new Date(v));
```

### Choices with locale-different names

Choice "Yes"/"No" in English vs other languages. FormattedValue returns according to user locale. **Don't match on localized strings** — use the int values.

### Required fields not in the template

Table has a required field that wasn't thought of in the template. Result: every row fails with 400. Solution: query schema via `mcp__dataverse__describe_table` and validate the template before distributing.

### Field length limits

`crd1_description` is nvarchar(100). CSV row has 150 chars. Result: 400 truncation error. Validate lengths in phase 4.

## Anti-patterns

### ❌ Sequential loops for bulk

`for (const r of records) await create(r)` is 100x slower. Always Promise.allSettled in batches.

### ❌ Trusting headers in fixed positions

User can rearrange columns in Excel. Always map by name (with normalization), not by index.

### ❌ Not handling empty rows

Excel has "ghost" rows at the end. `if (cells.every(c => c.trim() === '')) continue;`

### ❌ Skipping validation "to be faster"

Invisible errors appear weeks later as inconsistent data. Validate everything upfront, report to user, let them decide.
