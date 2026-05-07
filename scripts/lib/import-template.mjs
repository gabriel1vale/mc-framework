/**
 * Bulk import skeleton for Dataverse.
 *
 * COPY to `<project>/dataverse/scripts/` and adapt the ENV_URL, TARGET_TABLE,
 * SOURCE_FILE, and the COLUMN_MAPPING. The other functions are generic.
 *
 * Prerequisites:
 *   - inside a WSL distro with `az login` active
 *   - exceljs installed (npm i exceljs)
 *
 * Usage:
 *   node import.mjs --dry              # parse + match only, no writes
 *   node import.mjs                    # full run
 *   node import.mjs --no-wipe          # skip wipe phase (additive only)
 */

import ExcelJS from 'exceljs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  getDataverseToken, makeHeaders,
  dvGetAll, dvPost, dvDelete,
  chunk, sleep,
} from './token-from-az.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ============================================================================
// CONFIG - adapt per project
// ============================================================================
const ENV_URL       = 'https://CHANGE-ME.crm4.dynamics.com';   // env URL (no /api/data...)
const TARGET_TABLE  = 'CHANGE_ME_entitysetname';                // e.g. crd1_orderlines
const SOURCE_FILE   = path.resolve(__dirname, '../../data/import.xlsx');
const SHEET_NAME    = null;  // null = first sheet; or specific name

// Mapping from source column -> Dataverse field
// Examples:
//   { source: 'Reference', target: 'crd1_sku', type: 'string' }
//   { source: 'Account',   target: 'crd1_Account@odata.bind', type: 'lookup', lookupTable: 'accounts', lookupField: 'name' }
const COLUMN_MAPPING = [
  // CHANGE ME - populate per schema
  // { source: 'Header', target: 'crd1_field', type: 'string' | 'number' | 'boolean' | 'choice' | 'lookup', ... }
];

// Filter for wipe (only deletes records matching it)
// Empty ('') = delete everything. Use with care!
const WIPE_FILTER = '';

// Recalc rollups after import? (true if the table feeds rollup columns)
const RECALC_ROLLUPS = false;
const ROLLUP_PARENT_TABLE = '';   // e.g. 'crd1_products'
const ROLLUP_COLUMNS = [];         // e.g. ['crd1_stockcentral', 'crd1_stocknorth']

// ============================================================================
// CLI args
// ============================================================================
const args = new Set(process.argv.slice(2));
const DRY_RUN  = args.has('--dry');
const SKIP_WIPE = args.has('--no-wipe');

// ============================================================================
// Setup
// ============================================================================
console.log(`=== ${TARGET_TABLE} importer ===`);
console.log(`Mode: ${DRY_RUN ? 'DRY-RUN' : 'LIVE'}${SKIP_WIPE ? ' (no-wipe)' : ''}`);
console.log('');

const token = await getDataverseToken(ENV_URL);
const headers = makeHeaders(token);

// ============================================================================
// Phase 0: load reference data (lookups)
// ============================================================================
console.log('[0] Loading reference data for lookups...');
const lookupCaches = new Map();  // table -> Map<lookupValue, guid>

for (const m of COLUMN_MAPPING) {
  if (m.type !== 'lookup') continue;
  if (lookupCaches.has(m.lookupTable)) continue;

  const records = await dvGetAll(
    ENV_URL,
    `/${m.lookupTable}?$select=${m.lookupTable.replace(/s$/, '')}id,${m.lookupField}`,
    headers,
  );
  const idField = `${m.lookupTable.replace(/s$/, '')}id`;
  const map = new Map();
  for (const r of records) {
    if (r[m.lookupField]) map.set(String(r[m.lookupField]).trim(), r[idField]);
  }
  lookupCaches.set(m.lookupTable, map);
  console.log(`    ${m.lookupTable}: ${map.size} entries indexed by '${m.lookupField}'`);
}

// ============================================================================
// Phase 1: parse source
// ============================================================================
console.log('');
console.log('[1] Parsing source file...');
const wb = new ExcelJS.Workbook();
await wb.xlsx.readFile(SOURCE_FILE);
const sheet = SHEET_NAME ? wb.getWorksheet(SHEET_NAME) : wb.worksheets[0];
console.log(`    Sheet "${sheet.name}": ${sheet.rowCount} rows`);

// Header -> column index
const headerRow = sheet.getRow(1);
const colIndex = {};
for (let c = 1; c <= sheet.columnCount; c++) {
  const v = String(headerRow.getCell(c).value ?? '').trim();
  if (v) colIndex[v] = c;
}

// Validate all required columns present
for (const m of COLUMN_MAPPING) {
  if (!colIndex[m.source]) {
    throw new Error(`Source column "${m.source}" not found in sheet. Headers: ${Object.keys(colIndex).join(', ')}`);
  }
}

// Parse rows
const valid = [];
const invalid = [];

for (let r = 2; r <= sheet.rowCount; r++) {
  const row = sheet.getRow(r);
  const cells = {};
  for (let c = 1; c <= sheet.columnCount; c++) {
    const header = Object.keys(colIndex).find((k) => colIndex[k] === c);
    if (header) cells[header] = row.getCell(c).value;
  }
  if (Object.values(cells).every((v) => v === null || v === undefined || String(v).trim() === '')) continue;

  const errors = [];
  const payload = {};

  for (const m of COLUMN_MAPPING) {
    const raw = cells[m.source];
    const str = raw === null || raw === undefined ? '' : String(raw).trim();

    if (m.required && !str) {
      errors.push(`'${m.source}' missing`);
      continue;
    }
    if (!str) continue;

    if (m.type === 'string') payload[m.target] = str;
    else if (m.type === 'number') {
      const n = Number(str.replace(',', '.'));
      if (Number.isNaN(n)) errors.push(`'${m.source}' invalid (expected number): ${str}`);
      else payload[m.target] = n;
    }
    else if (m.type === 'boolean') {
      payload[m.target] = ['true', '1', 'yes', 'sim'].includes(str.toLowerCase());
    }
    else if (m.type === 'choice') {
      // m.choices: { 'Label': 100000000, ... }
      const code = m.choices?.[str] ?? m.choices?.[str.toLowerCase()];
      if (code === undefined) errors.push(`'${m.source}' value "${str}" not recognized`);
      else payload[m.target] = code;
    }
    else if (m.type === 'lookup') {
      const cache = lookupCaches.get(m.lookupTable);
      const guid = cache?.get(str);
      if (!guid) errors.push(`'${m.source}' lookup "${str}" not found in ${m.lookupTable}`);
      else payload[m.target] = `/${m.lookupTable}(${guid})`;
    }
    else {
      errors.push(`'${m.source}' unsupported type: ${m.type}`);
    }
  }

  if (errors.length > 0) {
    invalid.push({ rowNumber: r, raw: cells, errors });
  } else {
    valid.push({ rowNumber: r, payload });
  }
}

console.log(`    Total: ${sheet.rowCount - 1}; Valid: ${valid.length}; Invalid: ${invalid.length}`);

if (invalid.length > 0) {
  console.log('');
  console.log('Invalid rows (first 5):');
  invalid.slice(0, 5).forEach((i) => {
    console.log(`  row ${i.rowNumber}: ${i.errors.join('; ')}`);
  });
}

if (DRY_RUN) {
  console.log('');
  console.log('Dry-run sample valid payloads (first 3):');
  valid.slice(0, 3).forEach((v) => console.log(JSON.stringify(v, null, 2)));
  process.exit(0);
}

// ============================================================================
// Phase 2: wipe (optional)
// ============================================================================
if (!SKIP_WIPE) {
  console.log('');
  console.log('[2] Wiping target table...');
  const idField = TARGET_TABLE.replace(/es$/, '').replace(/s$/, '') + 'id';
  const filterPart = WIPE_FILTER ? `&$filter=${encodeURIComponent(WIPE_FILTER)}` : '';
  const existing = await dvGetAll(ENV_URL, `/${TARGET_TABLE}?$select=${idField}${filterPart}`, headers);
  console.log(`    ${existing.length} existing rows to delete.`);

  let deleted = 0;
  for (const batch of chunk(existing.map(e => e[idField]), 10)) {
    await Promise.all(batch.map((id) => dvDelete(ENV_URL, `/${TARGET_TABLE}(${id})`, headers)));
    deleted += batch.length;
    process.stdout.write(`    deleted ${deleted}/${existing.length}\r`);
  }
  console.log(`    deleted ${deleted}/${existing.length}                   `);
}

// ============================================================================
// Phase 3: bulk create
// ============================================================================
console.log('');
console.log('[3] Creating records...');

let created = 0;
const errors = [];
for (const batch of chunk(valid, 10)) {
  const results = await Promise.allSettled(
    batch.map((v) => dvPost(ENV_URL, `/${TARGET_TABLE}`, v.payload, headers)),
  );
  results.forEach((res, i) => {
    if (res.status === 'fulfilled') created++;
    else errors.push(`row ${batch[i].rowNumber}: ${res.reason.message}`);
  });
  process.stdout.write(`    created ${created}/${valid.length}\r`);
}
console.log(`    created ${created}/${valid.length}; errors: ${errors.length}              `);
if (errors.length > 0) {
  console.log('First errors:');
  errors.slice(0, 3).forEach((e) => console.log(`  ${e}`));
}

// ============================================================================
// Phase 4: recalc rollups (optional)
// ============================================================================
if (RECALC_ROLLUPS && ROLLUP_PARENT_TABLE && ROLLUP_COLUMNS.length > 0) {
  console.log('');
  console.log('[4] Recalculating rollups...');
  await sleep(2000);  // engine indexing

  // Identify affected parents (extract from payloads)
  // This part is schema-specific - adapt.
  // Example: if each record has 'parent_lookup@odata.bind' -> '/parents(GUID)'
  // Extract unique GUIDs.
  // const affected = new Set();
  // for (const v of valid) {
  //   const lookup = v.payload['parent_lookup@odata.bind'];
  //   if (lookup) {
  //     const m = lookup.match(/\(([^)]+)\)/);
  //     if (m) affected.add(m[1]);
  //   }
  // }

  // for (const parentId of affected) {
  //   for (const col of ROLLUP_COLUMNS) {
  //     const target = JSON.stringify({ '@odata.id': `${ROLLUP_PARENT_TABLE}(${parentId})` });
  //     const url = `${ENV_URL.replace(/\/$/, '')}/api/data/v9.2/CalculateRollupField(Target=@T,FieldName=@F)?@T=${encodeURIComponent(target)}&@F='${col}'`;
  //     await fetch(url, { headers });
  //   }
  // }
  // console.log(`    recalc: ${affected.size} parents x ${ROLLUP_COLUMNS.length} columns`);
}

console.log('');
console.log('=== DONE ===');
console.log(JSON.stringify({
  totalSource: sheet.rowCount - 1,
  valid: valid.length,
  invalid: invalid.length,
  created,
  errors: errors.length,
}, null, 2));
