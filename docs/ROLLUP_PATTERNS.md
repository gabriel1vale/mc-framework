# Rollup Patterns

Everything you need to know about rollup columns in Dataverse, including the famous empty-source bug.

## What a rollup column is

A rollup column on a parent record aggregates values from child records via a formula like:

```
SUM(crd1_orderlines.crd1_quantity) WHERE crd1_product = <this>
```

The formula is defined in maker (`make.powerapps.com`). Dataverse does not recalculate in real-time — there is a **rollup job** that runs periodically (default ~1h) and updates values in batch.

To force immediate recalculation there are two Custom APIs:

- `CalculateRollupField(Target, FieldName)` — recalc for a single record
- `MassCalculateRollupField(Target, FieldName)` — batch recalc for all records matching a filter

## Critical bug: empty-source keeps cached value

### Symptom

You delete all child records that feed a rollup. You call `CalculateRollupField` on the parent. **The value does not go to zero** — it stays at the last cached value.

`MassCalculateRollupField` has the same bug. It reports `state=Calculated` but with the old value.

### Cause (not officially documented)

The rollup engine appears to track via "dirty bits" on the relationship. When all children are deleted, there is no "dirty" to process, so the engine returns the last calculated value. Instead of doing `SUM([])` = 0, it does "skip recalc, return cached".

### Workaround: dummy-anchor pattern

```
1. Create a temporary child record with qty=0 and the lookup correctly populated
2. Wait 1-2s for the engine to index (important)
3. Call CalculateRollupField → engine sees non-empty source (1 record qty=0), does SUM = 0, writes
4. Verify the written value is 0; if not yet, retry (up to 3 times)
5. Delete the anchor — the engine doesn't touch deletes, the rollup stays at 0
```

### Why the lookup is essential

A dummy-anchor WITHOUT the populated lookup (only with the equivalent string like `crd1_regionname`) is **invisible** to the engine. Dirty tracking is via the lookup relationship. Always use `<your_lookup>@odata.bind: /...` in the anchor payload.

### Full implementation

Pseudo-code (TypeScript with `@microsoft/power-apps` SDK):

```typescript
const ANCHOR_BATCH = 10;
const MAX_RETRIES = 3;

async function recalcAllNonZeroStocks(onProgress: (msg: string) => void) {
  // Phase 0: load region map (lookup name → guid)
  const regions = await loadRegions();
  const regionIdByName: Record<string, string> = {};
  for (const t of regions) regionIdByName[t.label.trim()] = t.id;

  // Phase 1: identify (parent, rollup-column) pairs with non-zero value
  const ops: AnchorOp[] = [];
  // ... fetch all parents, iterate rollup columns, push pairs with value != 0

  if (ops.length === 0) return { ok: 0, failed: 0, errors: [] };

  // Phase 2: create anchors in parallel batches
  for (let i = 0; i < ops.length; i += ANCHOR_BATCH) {
    const chunk = ops.slice(i, i + ANCHOR_BATCH);
    const results = await Promise.allSettled(
      chunk.map((op) =>
        Crd1_orderlinesService.create({
          'crd1_Product@odata.bind': `/crd1_products(${op.productId})`,
          'crd1_Region@odata.bind': `/crd1_regions(${op.regionId})`,
          crd1_quantity: 0,
          crd1_type: TYPE_INBOUND,
        } as never),
      ),
    );
    // capture dummyId in op
  }

  // Phase 3: wait for engine to index
  await sleep(2000);

  // Phase 4: CalculateRollupField sequential with verify-and-retry
  for (const op of ops) {
    if (!op.dummyId) { failed++; continue; }
    let attempt = 0;
    let succeeded = false;
    while (attempt < MAX_RETRIES && !succeeded) {
      attempt++;
      onProgress(`Recalculating ${op.parentName}/${op.col} (attempt ${attempt})…`);
      const r = await recalcRollup(op.parentId, op.col);
      if (!r.ok) {
        await sleep(500);
        continue;
      }
      // Verify: read the value, see if it is actually 0
      const value = await fetchCurrentValue(op.parentId, op.col);
      if (value === 0) {
        succeeded = true;
        break;
      }
      await sleep(800);
    }
    if (succeeded) ok++;
    else failed++;
  }

  // Phase 5: cleanup anchors
  const anchored = ops.filter((op) => op.dummyId);
  for (const batch of chunk(anchored, ANCHOR_BATCH)) {
    await Promise.allSettled(batch.map((op) => Service.delete(op.dummyId!)));
  }

  return { ok, failed, errors };
}
```

### When to apply

- After bulk delete on the source table
- After reset operation (delete ALL children)
- When rollups appear stuck on the old value despite confirmed source changes

### When NOT needed

- After creating new children with populated lookup — engine recalcs fine on its own
- Updates to existing children (same pattern)
- When the source was never empty between the deletes and `CalculateRollupField`

## Recalc after bulk import

After creating many new children, you may want to force recalc of the affected parents' rollups (instead of waiting for the 1h job).

If the source is not empty (you just created records), vanilla `CalculateRollupField` works — no dummy-anchor needed:

```typescript
// For each unique (parent, rollupCol):
for (const pair of affectedPairs) {
  const target = JSON.stringify({ '@odata.id': `crd1_products(${pair.productId})` });
  await fetch(
    `${API_BASE}/CalculateRollupField(Target=@T,FieldName=@F)?@T=${encodeURIComponent(target)}&@F='${pair.col}'`,
    { headers: { Authorization: `Bearer ${token}` } }
  );
}
```

Sequential (the engine does not handle parallel well on this operation) or small batches of 3-5.

## Region/territory → rollup column mapping

Common pattern: parent table has rollup columns by region (e.g. `crd1_stocknorth`, `crd1_stockcentral`). Child table has `crd1_region` lookup to a `crd1_regions` table with multiple regions per logical zone.

Example:
- Regions "Central", "Central North", "Central South" → all consolidate into `crd1_stockcentral`
- Other regions 1:1 with columns

Map function:

```typescript
function mapRegionToColumn(name: string): string | null {
  if (!name) return null;
  const lower = name.toLowerCase().trim();
  if (lower.startsWith('central')) return 'crd1_stockcentral';
  if (lower.includes('north')) return 'crd1_stocknorth';
  if (lower.includes('south')) return 'crd1_stocksouth';
  if (lower.includes('east')) return 'crd1_stockeast';
  if (lower.includes('west')) return 'crd1_stockwest';
  return null;
}
```

(Genericize per client schema.)

## Anti-patterns

### ❌ Trust the natural rollup job

"Dataverse will recalc by itself in 1h." Yes, but:

- The user sees wrong stocks during that hour
- The job can fail silently (no UI to confirm)
- In development, waiting 1h for confirmation destroys the loop

Always force-recalc after significant changes.

### ❌ Delete children without dummy-anchor afterwards

Result: rollups stuck at the last non-zero value. UI lies to users. Apply the dummy-anchor pattern whenever you delete everything.

### ❌ `CalculateRollupField` in parallel

The engine doesn't handle concurrent calls well on the same column. Sequential (with `await sleep` between, if needed). For many parents, batches of 3-5 parallel are OK.

### ❌ Forgetting `await sleep(2000)` between creating anchor and recalc

Without this, recalc can fire before the engine indexes the anchor. It sees an empty source (from its perspective), returns cached. Anchors useless.

## Debug helpers

```typescript
async function fetchCurrentValue(parentId: string, columnName: string): Promise<number | null> {
  try {
    const result = await ParentService.get(parentId, { select: [columnName] });
    if (!result.success) return null;
    const value = (result.data as unknown as Record<string, unknown>)[columnName];
    return typeof value === 'number' ? value : 0;
  } catch {
    return null;
  }
}
```

Useful to verify that the recalc actually wrote the expected value.

## Microsoft reference

When in doubt, consult `microsoft-learn` MCP:

```
mcp__claude_ai_Microsoft_Learn__microsoft_docs_search("Dataverse rollup column CalculateRollupField")
```

For edge cases not covered here.
