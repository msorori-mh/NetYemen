#!/usr/bin/env node
// Static contract test: admin/app.js <-> supabase/migrations.
//
// Dependency-free. Run from anywhere:
//   node scripts/test_admin_console_contract.mjs
//
// Checks
//   (a) every RPC called as rpc('name', ...) is defined in a migration as
//       CREATE [OR REPLACE] FUNCTION public.name
//   (b) every key of an object-literal argument is a parameter name of some
//       definition of that function
//   (c) the settlement statuses used by the settlements view are a subset of
//       the list accepted by get_finance_settlement_batches
//   (d) the commission view converts percent -> fraction (divide by 100) and
//       can never send a value above 1
//   (e) no silent catch on data loads, no direct writes to user_roles
//
// Exits non-zero with one line per violation.

import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// ---------------------------------------------------------------------------
// PENDING_CONTRACT: items agreed in the remediation contract (CONTRACT.md,
// "Backend changes the lead is implementing in a new migration") that the
// console already builds against but that are NOT in supabase/migrations yet.
//   'function_name'            -> the whole function is still missing
//   'function_name.p_param'    -> the function exists, this parameter is new
// Delete an entry as soon as its migration lands (the test prints a notice
// when an entry is no longer needed). Do NOT add anything else here: an RPC
// that is neither in the migrations nor in the contract is a real bug.
// ---------------------------------------------------------------------------
const PENDING_CONTRACT = new Set([]);

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.dirname(scriptDirectory);
const appPath = path.join(repositoryRoot, 'admin', 'app.js');
const migrationsDirectory = path.join(repositoryRoot, 'supabase', 'migrations');

const failures = [];
const notices = [];
const fail = (message) => failures.push(message);
const note = (message) => notices.push(message);

const app = readFileSync(appPath, 'utf8');
const lineOf = (source, index) => source.slice(0, index).split('\n').length;

// ---------------------------------------------------------------------------
// Small scanners
// ---------------------------------------------------------------------------

// Index of the bracket that closes the one at `open`, skipping JS strings,
// regex-free: good enough for the ES5-style code in app.js.
function matchBracket(source, open) {
  const pairs = { '{': '}', '(': ')', '[': ']' };
  const closer = pairs[source[open]];
  if (!closer) throw new Error(`matchBracket: not a bracket at ${open}`);
  const stack = [closer];
  for (let i = open + 1; i < source.length; i += 1) {
    const ch = source[i];
    if (ch === "'" || ch === '"' || ch === '`') {
      i += 1;
      while (i < source.length && source[i] !== ch) {
        if (source[i] === '\\') i += 1;
        i += 1;
      }
      continue;
    }
    if (ch === '/' && source[i + 1] === '/') {
      while (i < source.length && source[i] !== '\n') i += 1;
      continue;
    }
    if (pairs[ch]) stack.push(pairs[ch]);
    else if (ch === stack[stack.length - 1]) {
      stack.pop();
      if (!stack.length) return i;
    }
  }
  throw new Error(`matchBracket: unbalanced bracket at ${open}`);
}

// Top-level keys of the object literal starting at `open` ('{').
function objectLiteralKeys(source, open) {
  const close = matchBracket(source, open);
  const keys = [];
  let depth = 0;
  let expectKey = true;
  for (let i = open + 1; i < close; i += 1) {
    const ch = source[i];
    if (ch === "'" || ch === '"') {
      const start = i;
      i += 1;
      while (i < close && source[i] !== ch) {
        if (source[i] === '\\') i += 1;
        i += 1;
      }
      if (depth === 0 && expectKey) {
        const after = source.slice(i + 1, close).match(/^\s*:/);
        if (after) { keys.push(source.slice(start + 1, i)); expectKey = false; }
      }
      continue;
    }
    if (ch === '/' && source[i + 1] === '/') {
      while (i < close && source[i] !== '\n') i += 1;
      continue;
    }
    if (ch === '{' || ch === '(' || ch === '[') { depth += 1; continue; }
    if (ch === '}' || ch === ')' || ch === ']') { depth -= 1; continue; }
    if (depth !== 0) continue;
    if (ch === ',') { expectKey = true; continue; }
    if (expectKey && /[A-Za-z_$]/.test(ch)) {
      const m = source.slice(i, close).match(/^([A-Za-z_$][\w$]*)\s*:/);
      if (m) { keys.push(m[1]); i += m[1].length - 1; }
      expectKey = false;
    }
  }
  return keys;
}

// ---------------------------------------------------------------------------
// Migrations: every definition of every public function
// ---------------------------------------------------------------------------

function stripSqlComments(sql) {
  return sql.replace(/--[^\n]*/g, '');
}

function splitTopLevel(text) {
  const parts = [];
  let depth = 0;
  let current = '';
  let quote = null;
  for (const ch of text) {
    if (quote) {
      current += ch;
      if (ch === quote) quote = null;
      continue;
    }
    if (ch === "'" || ch === '"') { quote = ch; current += ch; continue; }
    if (ch === '(' || ch === '[') depth += 1;
    if (ch === ')' || ch === ']') depth -= 1;
    if (ch === ',' && depth === 0) { parts.push(current); current = ''; continue; }
    current += ch;
  }
  if (current.trim()) parts.push(current);
  return parts.map((part) => part.trim()).filter(Boolean);
}

// name -> [{ file, params: [{ name, hasDefault }], body }], in migration order
const functions = new Map();
const migrationFiles = readdirSync(migrationsDirectory).filter((f) => f.endsWith('.sql')).sort();
if (!migrationFiles.length) fail(`No .sql migrations found in ${migrationsDirectory}`);

for (const file of migrationFiles) {
  const sql = stripSqlComments(readFileSync(path.join(migrationsDirectory, file), 'utf8'));
  const re = /create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-z_][a-z0-9_]*)\s*\(/gi;
  let m;
  while ((m = re.exec(sql))) {
    const open = m.index + m[0].length - 1;
    let close;
    try { close = matchBracket(sql, open); } catch { continue; }
    const params = splitTopLevel(sql.slice(open + 1, close)).map((raw) => {
      const tokens = raw.split(/\s+/);
      let nameToken = tokens[0];
      if (/^(in|out|inout|variadic)$/i.test(nameToken)) nameToken = tokens[1];
      return {
        name: String(nameToken || '').toLowerCase().replace(/"/g, ''),
        hasDefault: /\sdefault\s|=/i.test(raw),
      };
    });
    // Body: between the first pair of dollar-quote tags after the signature.
    const tail = sql.slice(close);
    const tag = tail.match(/\$[A-Za-z_]*\$/);
    let body = '';
    if (tag) {
      const start = tail.indexOf(tag[0]) + tag[0].length;
      const end = tail.indexOf(tag[0], start);
      body = end === -1 ? '' : tail.slice(start, end);
    }
    const name = m[1].toLowerCase();
    if (!functions.has(name)) functions.set(name, []);
    functions.get(name).push({ file, params, body });
  }
}

const finalDefinition = (name) => {
  const defs = functions.get(name);
  return defs ? defs[defs.length - 1] : null;
};

// ---------------------------------------------------------------------------
// (a) + (b): RPC names and parameter names
// ---------------------------------------------------------------------------

const usedPending = new Set();
const rpcCallRe = /\brpc\(\s*(['"])([A-Za-z_][\w]*)\1/g;
const rpcCalls = [];
let call;
while ((call = rpcCallRe.exec(app))) {
  const name = call[2];
  const line = lineOf(app, call.index);
  let rest = call.index + call[0].length;
  while (/\s/.test(app[rest])) rest += 1;
  let keys = null;
  if (app[rest] === ',') {
    rest += 1;
    while (/\s/.test(app[rest])) rest += 1;
    if (app[rest] === '{') {
      keys = objectLiteralKeys(app, rest);
    } else {
      // rpc('name', someVariable): resolve `var someVariable = { ... }` declared before the call.
      const ident = app.slice(rest).match(/^([A-Za-z_$][\w$]*)\s*\)/);
      if (ident) {
        const declRe = new RegExp(`\\bvar\\s+${ident[1].replace(/\$/g, '\\$')}\\s*=\\s*\\{`, 'g');
        let decl;
        let lastDecl = null;
        while ((decl = declRe.exec(app)) && decl.index < call.index) lastDecl = decl;
        if (lastDecl) keys = objectLiteralKeys(app, lastDecl.index + lastDecl[0].length - 1);
        else fail(`admin/app.js:${line}: rpc('${name}', ${ident[1]}) — cannot resolve the argument to an object literal; pass a literal so its keys can be checked.`);
      } else {
        fail(`admin/app.js:${line}: rpc('${name}', ...) — argument is not an object literal or a plain variable; cannot check its keys.`);
      }
    }
  }
  rpcCalls.push({ name, line, keys });
}

if (rpcCalls.length < 20) fail(`Only ${rpcCalls.length} rpc('...') calls found in admin/app.js — the scanner is probably broken.`);

for (const { name, line, keys } of rpcCalls) {
  const defs = functions.get(name.toLowerCase());
  if (!defs) {
    if (PENDING_CONTRACT.has(name)) { usedPending.add(name); continue; }
    fail(`admin/app.js:${line}: RPC '${name}' is not defined in supabase/migrations (no CREATE FUNCTION public.${name}).`);
    continue;
  }
  if (!keys) continue;
  const everyParam = new Set(defs.flatMap((d) => d.params.map((p) => p.name)));
  const last = defs[defs.length - 1];
  const lastParams = new Set(last.params.map((p) => p.name));
  for (const key of keys) {
    const pendingKey = `${name}.${key}`;
    if (!everyParam.has(key.toLowerCase())) {
      if (PENDING_CONTRACT.has(pendingKey)) { usedPending.add(pendingKey); continue; }
      fail(`admin/app.js:${line}: rpc('${name}') sends '${key}', which is not a parameter of any definition of public.${name} (final signature: ${[...lastParams].join(', ') || 'no parameters'}).`);
    } else if (!lastParams.has(key.toLowerCase())) {
      note(`admin/app.js:${line}: rpc('${name}') sends '${key}', found only in an older definition, not in the final one (${last.file}).`);
    }
  }
  for (const param of last.params) {
    if (!param.hasDefault && !keys.includes(param.name)) {
      note(`admin/app.js:${line}: rpc('${name}') omits '${param.name}', which has no DEFAULT in ${last.file}.`);
    }
  }
}

for (const entry of PENDING_CONTRACT) {
  const [fn, param] = entry.split('.');
  const defs = functions.get(fn);
  const landed = param ? !!defs && defs.some((d) => d.params.some((p) => p.name === param)) : !!defs;
  if (landed) note(`PENDING_CONTRACT entry '${entry}' is now present in the migrations — delete it from the allow-list.`);
  else if (!usedPending.has(entry)) note(`PENDING_CONTRACT entry '${entry}' is not used by admin/app.js — delete it from the allow-list.`);
}

// ---------------------------------------------------------------------------
// Helpers to cut a named piece out of app.js
// ---------------------------------------------------------------------------

function viewSource(name) {
  const marker = `views.${name} = function`;
  const start = app.indexOf(marker);
  if (start === -1) { fail(`admin/app.js: views.${name} not found.`); return ''; }
  const open = app.indexOf('{', start);
  return app.slice(start, matchBracket(app, open) + 1);
}

function functionSource(name) {
  const m = new RegExp(`\\bfunction\\s+${name}\\s*\\(`).exec(app);
  if (!m) { fail(`admin/app.js: function ${name} not found.`); return ''; }
  const open = app.indexOf('{', matchBracket(app, m.index + m[0].length - 1));
  return app.slice(m.index, matchBracket(app, open) + 1);
}

// ---------------------------------------------------------------------------
// (c) settlement statuses
// ---------------------------------------------------------------------------

{
  const def = finalDefinition('get_finance_settlement_batches');
  const serverList = def && def.body.match(/p_status\s+NOT\s+IN\s*\(([^)]*)\)/i);
  if (!serverList) {
    fail('Cannot read the accepted status list from the final get_finance_settlement_batches definition.');
  } else {
    const server = new Set([...serverList[1].matchAll(/'([^']+)'/g)].map((x) => x[1]));
    const declared = app.match(/var\s+SETTLEMENT_STATUSES\s*=\s*\[([^\]]*)\]/);
    const view = viewSource('settlements');
    const used = new Map(); // status -> where
    if (!declared) fail('admin/app.js: var SETTLEMENT_STATUSES = [...] not found.');
    else for (const x of declared[1].matchAll(/'([^']+)'/g)) used.set(x[1], 'SETTLEMENT_STATUSES');
    // b.status === 'x' / b.status !== 'x'
    for (const x of view.matchAll(/\.status\s*[!=]==\s*'([^']+)'/g)) used.set(x[1], 'batch status comparison');
    // status = 'x' (default / fallback filter value), not ==/===
    for (const x of view.matchAll(/(?<![!=.\w])status\s*=(?!=)\s*'([^']+)'/g)) used.set(x[1], 'default filter value');
    // sessionStorage.setItem('settlementFilter', 'x')
    for (const x of view.matchAll(/setItem\(\s*'settlementFilter'\s*,\s*'([^']+)'/g)) used.set(x[1], 'stored filter value');
    if (!used.size) fail('admin/app.js: no settlement statuses found in the settlements view — scanner broken?');
    for (const [status, where] of used) {
      if (!server.has(status)) {
        fail(`admin/app.js settlements view uses status '${status}' (${where}); the server accepts only: ${[...server].join(', ')}.`);
      }
    }
    for (const status of server) {
      if (!used.has(status)) note(`Settlement status '${status}' is accepted by the server but has no filter in the console.`);
    }
    if (!/rpc\(\s*'get_finance_settlement_batches'\s*,\s*\{\s*p_status\s*:/.test(view)) {
      fail("admin/app.js settlements view must call rpc('get_finance_settlement_batches', { p_status: ... }).");
    }
    const approve = finalDefinition('finance_approve_settlement_batch');
    const approveFrom = approve && approve.body.match(/status\s+NOT\s+IN\s*\(([^)]*)\)/i);
    if (approveFrom) {
      const approveLine = view.split('\n').find((l) => l.includes('data-approve-set="')) || '';
      const guardIndex = view.indexOf('data-approve-set="');
      const guard = view.slice(Math.max(0, guardIndex - 700), guardIndex);
      for (const x of approveFrom[1].matchAll(/'([^']+)'/g)) {
        if (!guard.includes(`'${x[1]}'`)) {
          fail(`admin/app.js settlements view: the approve button must be offered for status '${x[1]}' (finance_approve_settlement_batch approves from it).${approveLine ? '' : ' Approve button not found.'}`);
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// (d) commission: percent in the UI, fraction (0..1) on the wire
// ---------------------------------------------------------------------------

{
  const view = viewSource('commission');
  const converterSource = functionSource('commissionPercentToFraction');
  const updateCalls = [...app.matchAll(/rpc\(\s*'admin_update_default_commission_rate'\s*,\s*\{([^}]*)\}/g)];
  if (updateCalls.length !== 1) {
    fail(`admin/app.js must call admin_update_default_commission_rate exactly once with an object literal (found ${updateCalls.length}).`);
  } else {
    const arg = updateCalls[0][1].trim();
    const m = arg.match(/^p_rate\s*:\s*([A-Za-z_$][\w$]*)$/);
    if (!m) {
      fail(`admin/app.js: admin_update_default_commission_rate must be called as { p_rate: <variable> } (found { ${arg} }).`);
    } else {
      const assign = new RegExp(`\\bvar\\s+${m[1]}\\s*=\\s*commissionPercentToFraction\\(`);
      if (!assign.test(view)) {
        fail(`admin/app.js commission view: '${m[1]}' sent as p_rate must come straight from commissionPercentToFraction(...).`);
      }
      const reassigned = new RegExp(`(?<![\\w$.])${m[1]}\\s*(?:[-+*/]?=)(?!=)`, 'g');
      if ((view.match(reassigned) || []).length !== 1) {
        fail(`admin/app.js commission view: '${m[1]}' must be assigned exactly once (no later re-scaling).`);
      }
      if (new RegExp(`if\\s*\\(\\s*${m[1]}\\s*===\\s*null\\s*\\)\\s*return`).test(view) === false) {
        fail(`admin/app.js commission view: must stop when commissionPercentToFraction returns null.`);
      }
    }
  }
  if ((app.match(/\bp_rate\s*:/g) || []).length !== 1) fail('admin/app.js: p_rate must be sent from exactly one place.');
  if (!/rpc\(\s*'get_platform_commission_config'\s*\)/.test(view)) {
    fail("admin/app.js commission view must load the current rate with rpc('get_platform_commission_config').");
  }
  if (!/سيتم تغيير العمولة من /.test(view) || !/asyncConfirm\(/.test(view)) {
    fail('admin/app.js commission view must confirm with a message restating the old and the new rate.');
  }
  if (/window\.confirm|[^A-Za-z]confirm\(/.test(view.replace(/asyncConfirm\(/g, ''))) {
    fail('admin/app.js commission view must use the console modal (asyncConfirm), not window.confirm.');
  }

  if (converterSource) {
    if (!/\/\s*100\b/.test(converterSource)) fail('commissionPercentToFraction must divide the percent by 100.');
    let convert = null;
    try { convert = new Function(`return (${converterSource});`)(); } catch (e) { fail(`commissionPercentToFraction cannot be evaluated: ${e.message}`); }
    if (convert) {
      const expectations = [
        ['0', 0], ['1', 0.01], ['3', 0.03], ['3.5', 0.035], ['12.5', 0.125], ['99.9', 0.999], ['100', 1], [' 5 ', 0.05], [7, 0.07],
        ['', null], ['abc', null], ['-1', null], ['100.1', null], ['101', null], ['1000', null], ['1e2', null],
        ['0x10', null], ['3.55', null], ['.5', null], ['5.', null], ['Infinity', null], ['NaN', null], [null, null], [undefined, null],
      ];
      for (const [input, expected] of expectations) {
        const actual = convert(input);
        if (actual !== expected) {
          fail(`commissionPercentToFraction(${JSON.stringify(input) ?? 'undefined'}) returned ${actual}, expected ${expected}.`);
        }
      }
      for (let tenths = 0; tenths <= 1000; tenths += 1) {
        const text = tenths % 10 === 0 ? String(tenths / 10) : `${Math.floor(tenths / 10)}.${tenths % 10}`;
        const actual = convert(text);
        if (typeof actual !== 'number' || !(actual >= 0 && actual <= 1) || Math.abs(actual - tenths / 1000) > 1e-9) {
          fail(`commissionPercentToFraction('${text}') returned ${actual}; expected ${tenths / 1000} (never above 1).`);
          break;
        }
      }
      for (const big of ['100.5', '150', '999', '1e3', '100000']) {
        const actual = convert(big);
        if (actual !== null) fail(`commissionPercentToFraction('${big}') returned ${actual}; values above 100% must be rejected.`);
      }
    }
  }

  const server = finalDefinition('admin_update_default_commission_rate');
  if (!server) fail('admin_update_default_commission_rate is not defined in the migrations.');
  else if (!/p_rate\s*>\s*1\b/.test(server.body)) {
    fail('admin_update_default_commission_rate no longer rejects p_rate > 1: the server unit changed, re-check the console conversion.');
  }
}

// ---------------------------------------------------------------------------
// (e) hygiene the remediation contract relies on
// ---------------------------------------------------------------------------

{
  const silent = /\.catch\(\s*function\s*\(\s*\w*\s*\)\s*\{\s*(?:return\s*(?:\[\s*\]|\{\s*\}|null|undefined)?\s*;?)?\s*\}\s*\)/g;
  let m;
  while ((m = silent.exec(app))) {
    fail(`admin/app.js:${lineOf(app, m.index)}: silent catch (${m[0].replace(/\s+/g, ' ')}) — a failed load must show an error, not an empty result.`);
  }
  const write = /\.from\(\s*'user_roles'\s*\)\s*\.\s*(insert|update|upsert|delete)\s*\(/g;
  while ((m = write.exec(app))) {
    fail(`admin/app.js:${lineOf(app, m.index)}: direct ${m[1]} on user_roles — role changes must go through admin_set_user_platform_role / admin_replace_user_platform_roles.`);
  }
  const roleDef = finalDefinition('admin_set_user_platform_role');
  const allowed = roleDef && roleDef.body.match(/v_allowed_roles[^;]*ARRAY\s*\[([^\]]*)\]/i);
  const declared = app.match(/var\s+ASSIGNABLE_PLATFORM_ROLES\s*=\s*\[([^\]]*)\]/);
  if (allowed && declared) {
    const server = new Set([...allowed[1].matchAll(/'([^']+)'/g)].map((x) => x[1]));
    for (const x of declared[1].matchAll(/'([^']+)'/g)) {
      if (!server.has(x[1])) fail(`admin/app.js: role '${x[1]}' is offered in the roles dialog but admin_set_user_platform_role rejects it.`);
    }
  } else {
    fail('Cannot compare ASSIGNABLE_PLATFORM_ROLES with v_allowed_roles of admin_set_user_platform_role.');
  }
  const typeCheck = readFileSync(path.join(migrationsDirectory, migrationFiles.find((f) => /network_packages/.test(f)) || migrationFiles[0]), 'utf8')
    .match(/package_type\s+IN\s*\(([^)]*)\)/i);
  const packageTypes = app.match(/var\s+PACKAGE_TYPES\s*=\s*\[([\s\S]*?)\];/);
  if (typeCheck && packageTypes) {
    const server = new Set([...typeCheck[1].matchAll(/'([^']+)'/g)].map((x) => x[1]));
    for (const x of packageTypes[1].matchAll(/\[\s*'([^']+)'/g)) {
      if (!server.has(x[1])) fail(`admin/app.js: package type '${x[1]}' violates the network_packages CHECK (${[...server].join(', ')}).`);
    }
  } else {
    fail('Cannot compare PACKAGE_TYPES with the network_packages package_type CHECK.');
  }
}

// ---------------------------------------------------------------------------

for (const message of notices) console.log(`note: ${message}`);
if (failures.length) {
  console.error(`\nFAIL: admin console contract — ${failures.length} violation(s):`);
  for (const message of failures) console.error(`  - ${message}`);
  process.exit(1);
}
console.log(`\nOK: admin console contract — ${rpcCalls.length} RPC calls (${new Set(rpcCalls.map((c) => c.name)).size} distinct) checked against ${migrationFiles.length} migrations.`);
