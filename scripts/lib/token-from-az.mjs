/**
 * Helper to obtain a Dataverse Bearer token via az CLI.
 *
 * Usage (from other scripts):
 *
 *   import { getDataverseToken, makeHeaders } from './lib/token-from-az.mjs';
 *
 *   const token = await getDataverseToken('https://example.crm4.dynamics.com');
 *   const headers = makeHeaders(token);
 *   const r = await fetch(`${envUrl}/api/data/v9.2/...`, { headers });
 *
 * Prerequisite: inside a WSL distro with `az login` active.
 */

import { exec } from 'node:child_process';
import { promisify } from 'node:util';
const execAsync = promisify(exec);

/**
 * Obtains an access token for Dataverse via az CLI.
 * @param {string} envUrl - Environment URL (with or without trailing slash, e.g. 'https://example.crm4.dynamics.com')
 * @returns {Promise<string>} JWT Bearer token
 */
export async function getDataverseToken(envUrl) {
  const resource = envUrl.endsWith('/') ? envUrl : `${envUrl}/`;
  const cmd = `az account get-access-token --resource ${resource} --query accessToken -o tsv`;
  try {
    const { stdout } = await execAsync(cmd);
    const token = stdout.trim();
    if (!token || token.length < 100) {
      throw new Error('Returned token looks invalid (too short).');
    }
    return token;
  } catch (err) {
    throw new Error(
      `Failed to obtain token via az: ${err.message}\n` +
      `Check you are authenticated: az account show\n` +
      `If not, run: az login --use-device-code`
    );
  }
}

/**
 * Standard headers for Dataverse Web API calls.
 * @param {string} token - Bearer token (from getDataverseToken)
 * @returns {Record<string, string>}
 */
export function makeHeaders(token) {
  return {
    Authorization: `Bearer ${token}`,
    Accept: 'application/json',
    'OData-MaxVersion': '4.0',
    'OData-Version': '4.0',
    'Content-Type': 'application/json',
    Prefer: 'return=representation',
  };
}

/**
 * GET with automatic pagination (follows @odata.nextLink).
 */
export async function dvGetAll(envUrl, pathRel, headers) {
  const out = [];
  const apiBase = `${envUrl.replace(/\/$/, '')}/api/data/v9.2`;
  let url = `${apiBase}${pathRel}`;
  while (url) {
    const r = await fetch(url, { headers: { ...headers, Prefer: 'odata.maxpagesize=5000' } });
    if (!r.ok) throw new Error(`GET ${url} -> ${r.status} ${await r.text()}`);
    const j = await r.json();
    out.push(...(j.value ?? []));
    url = j['@odata.nextLink'] ?? null;
  }
  return out;
}

export async function dvPost(envUrl, pathRel, body, headers) {
  const apiBase = `${envUrl.replace(/\/$/, '')}/api/data/v9.2`;
  const r = await fetch(`${apiBase}${pathRel}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`POST ${pathRel} -> ${r.status} ${await r.text()}`);
  return r.json();
}

export async function dvDelete(envUrl, pathRel, headers) {
  const apiBase = `${envUrl.replace(/\/$/, '')}/api/data/v9.2`;
  const r = await fetch(`${apiBase}${pathRel}`, { method: 'DELETE', headers });
  if (!r.ok && r.status !== 404) {
    throw new Error(`DELETE ${pathRel} -> ${r.status} ${await r.text()}`);
  }
}

/**
 * Splits an array into chunks of N.
 */
export function chunk(arr, n) {
  const out = [];
  for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n));
  return out;
}

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
