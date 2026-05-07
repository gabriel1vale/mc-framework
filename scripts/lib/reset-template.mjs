/**
 * Bulk reset/wipe skeleton for Dataverse.
 *
 * COPY to `<project>/dataverse/scripts/` and adapt.
 *
 * What it does:
 *   1. Deletes records matching WIPE_FILTER (or all)
 *   2. Recalculates rollups of affected parents (with dummy-anchor pattern for empty source)
 *
 * Prerequisites:
 *   - inside a WSL distro with `az login` active
 *   - human confirmation before executing
 *
 * Usage:
 *   node reset.mjs --dry              # preview, no changes
 *   node reset.mjs                    # full run
 */

import {
  getDataverseToken, makeHeaders,
  dvGetAll, dvPost, dvDelete,
  chunk, sleep,
} from './token-from-az.mjs';

// ============================================================================
// CONFIG - adapt per project
// ============================================================================
const ENV_URL       = 'https://CHANGE-ME.crm4.dynamics.com';
const TARGET_TABLE  = 'CHANGE_ME_entitysetname';
const TARGET_ID_FIELD = 'CHANGE_ME_id';   // e.g. 'crd1_orderlineid'

// Filter for wipe (empty = delete EVERYTHING)
const WIPE_FILTER = '';

// Recalc rollups afterwards?
const RECALC_ROLLUPS = false;
const ROLLUP_PARENT_TABLE = '';   // e.g. 'crd1_products'
const ROLLUP_PARENT_ID_FIELD = '';  // e.g. 'crd1_productid'
const ROLLUP_COLUMNS = [];         // e.g. ['crd1_stockcentral', ...]
const PARENT_LOOKUP_FIELD = '';    // in the target table record, which field points to the parent (e.g. '_crd1_product_value')

// Dummy-anchor pattern: for the rollup to return 0 on empty source, we create a qty=0 anchor
// and then delete it. Adapt payload per schema.
const ANCHOR_PAYLOAD_TEMPLATE = {
  // CHANGE ME: must include the populated parent lookup and the minimum
  // fields for the record to be valid (e.g. type=Inbound, qty=0).
  // Example:
  //   '<lookup>@odata.bind': null  (populated by parent ID)
  //   field_qty: 0,
  //   field_type: 100000000,
};

// ============================================================================

const DRY_RUN = process.argv.includes('--dry');

console.log(`=== ${TARGET_TABLE} reset ===`);
console.log(`Mode: ${DRY_RUN ? 'DRY-RUN' : 'LIVE'}`);
if (WIPE_FILTER) console.log(`Filter: ${WIPE_FILTER}`);
else console.log('Filter: NONE (deletes EVERYTHING)');
console.log('');

const token = await getDataverseToken(ENV_URL);
const headers = makeHeaders(token);

// ============================================================================
// Phase 1: identify records
// ============================================================================
console.log('[1] Identifying records to delete...');
const filterPart = WIPE_FILTER ? `&$filter=${encodeURIComponent(WIPE_FILTER)}` : '';
const selectFields = [TARGET_ID_FIELD];
if (PARENT_LOOKUP_FIELD) selectFields.push(PARENT_LOOKUP_FIELD);

const existing = await dvGetAll(
  ENV_URL,
  `/${TARGET_TABLE}?$select=${selectFields.join(',')}${filterPart}`,
  headers,
);

console.log(`    ${existing.length} records found.`);

if (existing.length === 0) {
  console.log('Nothing to delete. Exit.');
  process.exit(0);
}

// Identify affected parents (for recalc later)
const affectedParents = new Set();
if (RECALC_ROLLUPS && PARENT_LOOKUP_FIELD) {
  for (const r of existing) {
    const parentId = r[PARENT_LOOKUP_FIELD];
    if (parentId) affectedParents.add(parentId);
  }
  console.log(`    ${affectedParents.size} parents will need rollup recalc.`);
}

if (DRY_RUN) {
  console.log('');
  console.log('Dry-run sample (first 5):');
  existing.slice(0, 5).forEach((r) => console.log(JSON.stringify(r)));
  process.exit(0);
}

// ============================================================================
// Phase 2: confirmation
// ============================================================================
console.log('');
console.log(`Will delete ${existing.length} records from '${TARGET_TABLE}'.`);
console.log('This operation is irreversible.');
console.log('');
process.stdout.write('Type "DELETE" to confirm: ');

// Read line from stdin
const readline = await import('node:readline/promises');
const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const answer = await rl.question('');
rl.close();

if (answer.trim() !== 'DELETE') {
  console.log('Cancelled.');
  process.exit(0);
}

// ============================================================================
// Phase 3: bulk delete
// ============================================================================
console.log('');
console.log('[2] Deleting...');
let deleted = 0;
const ids = existing.map((r) => r[TARGET_ID_FIELD]);
for (const batch of chunk(ids, 10)) {
  await Promise.all(batch.map((id) => dvDelete(ENV_URL, `/${TARGET_TABLE}(${id})`, headers)));
  deleted += batch.length;
  process.stdout.write(`    deleted ${deleted}/${ids.length}\r`);
}
console.log(`    deleted ${deleted}/${ids.length}                       `);

// ============================================================================
// Phase 4: recalc rollups with dummy-anchor (because source becomes empty)
// ============================================================================
if (RECALC_ROLLUPS && ROLLUP_PARENT_TABLE && ROLLUP_COLUMNS.length > 0 && affectedParents.size > 0) {
  console.log('');
  console.log('[3] Recalculating rollups (dummy-anchor pattern)...');

  const apiBase = `${ENV_URL.replace(/\/$/, '')}/api/data/v9.2`;
  let recalcOk = 0;
  let recalcFail = 0;

  for (const parentId of affectedParents) {
    for (const col of ROLLUP_COLUMNS) {
      // Phase 4a: create anchor (qty=0)
      // ATTENTION: ANCHOR_PAYLOAD_TEMPLATE must be adapted to populate the parent lookup correctly.
      const anchorPayload = JSON.parse(JSON.stringify(ANCHOR_PAYLOAD_TEMPLATE));
      // Example injection:
      // anchorPayload['<parent-lookup>@odata.bind'] = `/${ROLLUP_PARENT_TABLE}(${parentId})`;

      let anchorId;
      try {
        const created = await dvPost(ENV_URL, `/${TARGET_TABLE}`, anchorPayload, headers);
        anchorId = created[TARGET_ID_FIELD];
      } catch (err) {
        recalcFail++;
        continue;
      }

      // Phase 4b: wait for engine to index
      await sleep(2000);

      // Phase 4c: CalculateRollupField with retry
      const target = JSON.stringify({ '@odata.id': `${ROLLUP_PARENT_TABLE}(${parentId})` });
      const recalcUrl = `${apiBase}/CalculateRollupField(Target=@T,FieldName=@F)?@T=${encodeURIComponent(target)}&@F='${col}'`;

      let succeeded = false;
      for (let attempt = 0; attempt < 3 && !succeeded; attempt++) {
        try {
          const r = await fetch(recalcUrl, { headers });
          if (r.ok) {
            // Verify: read parent and confirm column is 0
            const verify = await dvGetAll(ENV_URL, `/${ROLLUP_PARENT_TABLE}(${parentId})?$select=${col}`, headers);
            const value = verify[0]?.[col];
            if (value === 0) {
              succeeded = true;
              recalcOk++;
              break;
            }
          }
        } catch {}
        await sleep(800);
      }
      if (!succeeded) recalcFail++;

      // Phase 4d: cleanup anchor (even if recalc failed)
      try {
        if (anchorId) await dvDelete(ENV_URL, `/${TARGET_TABLE}(${anchorId})`, headers);
      } catch {}
    }
  }

  console.log(`    recalc ok=${recalcOk} fail=${recalcFail} (of ${affectedParents.size} parents x ${ROLLUP_COLUMNS.length} cols)`);
}

console.log('');
console.log('=== DONE ===');
console.log(JSON.stringify({ deleted, recalcOk: 0, recalcFail: 0 }, null, 2));
