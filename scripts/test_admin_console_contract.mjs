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
//   (f) settlements: cancel / pay / negative net follow the server rules
//   (g) wallet freeze/unfreeze sends only the statuses the server accepts
//   (h) every key the console READS from an RPC result is produced by the
//       final definition of that function (return-shape check)
//   (i) direct table reads name only columns that exist in the migrations
//       and never the revoked compensation columns
//   (j) the console knows the error codes the server raises for its RPCs
//   (k) CSP-safe markup: no inline scripts/handlers, esc() escapes & < > " ',
//       vercel.json is valid and keeps script-src free of unsafe-*
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
    // `returns`: the text between the parameter list and the body (RETURNS ..., LANGUAGE ...).
    const returns = tag ? tail.slice(1, tail.indexOf(tag[0])) : '';
    functions.get(name).push({ file, params, body, returns });
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
// (f) settlements: cancel, payment reference, negative net
// ---------------------------------------------------------------------------

{
  const view = viewSource('settlements');
  const cancel = finalDefinition('finance_cancel_settlement_batch');
  if (!cancel) {
    fail('finance_cancel_settlement_batch is not defined in the migrations.');
  } else {
    if (!/rpc\(\s*'finance_cancel_settlement_batch'\s*,\s*\{\s*p_batch_id\s*:[^}]*p_reason\s*:/.test(view)) {
      fail("admin/app.js settlements view must call rpc('finance_cancel_settlement_batch', { p_batch_id, p_reason }).");
    }
    const cancelFrom = cancel.body.match(/status\s+NOT\s+IN\s*\(([^)]*)\)/i);
    const guardIndex = view.indexOf('data-cancel-set="');
    if (guardIndex === -1) fail('admin/app.js settlements view: cancel button (data-cancel-set) not found.');
    else if (cancelFrom) {
      const guard = view.slice(Math.max(0, guardIndex - 200), guardIndex);
      const allowed = [...cancelFrom[1].matchAll(/'([^']+)'/g)].map((x) => x[1]);
      for (const status of allowed) {
        if (!guard.includes(`'${status}'`)) fail(`admin/app.js settlements view: the cancel button must be offered for status '${status}'.`);
      }
      for (const x of guard.matchAll(/\.status\s*===\s*'([^']+)'/g)) {
        if (!allowed.includes(x[1])) fail(`admin/app.js settlements view: cancel is offered for status '${x[1]}', which finance_cancel_settlement_batch rejects.`);
      }
    }
    if (/REASON_REQUIRED/.test(cancel.body) && !/cancel-reason[\s\S]{0,400}if\s*\(\s*!reason\s*\)/.test(view)) {
      fail('admin/app.js settlements view: cancelling must require a non-empty reason before calling the RPC.');
    }
  }
  const pay = finalDefinition('finance_mark_settlement_paid');
  if (pay && /PAYMENT_REFERENCE_REQUIRED/.test(pay.body)) {
    if (!/if\s*\(\s*!notes\s*\)[^\n]*return false;[\s\S]{0,300}rpc\(\s*'finance_mark_settlement_paid'/.test(view)) {
      fail('admin/app.js settlements view: marking a batch paid must stop on an empty payment reference (server raises PAYMENT_REFERENCE_REQUIRED).');
    }
    if (!/PAYMENT_REFERENCE_REQUIRED\s*:/.test(app)) fail('admin/app.js: errText must translate PAYMENT_REFERENCE_REQUIRED.');
  }
  if (!/net\s*<\s*0/.test(view) || !/مستحق على المالك/.test(view)) {
    fail('admin/app.js settlements view: a batch with a negative net_settlement must be shown as an amount owed by the owner.');
  }
}

// ---------------------------------------------------------------------------
// (g) wallet status
// ---------------------------------------------------------------------------

{
  const def = finalDefinition('admin_set_wallet_status');
  const calls = [...app.matchAll(/rpc\(\s*'admin_set_wallet_status'\s*,\s*\{([^}]*)\}/g)];
  if (!def) fail('admin_set_wallet_status is not defined in the migrations.');
  else if (!calls.length) note('admin/app.js does not call admin_set_wallet_status.');
  else {
    const accepted = def.body.match(/p_status\s+NOT\s+IN\s*\(([^)]*)\)/i);
    const server = new Set(accepted ? [...accepted[1].matchAll(/'([^']+)'/g)].map((x) => x[1]) : []);
    if (!server.size) fail('Cannot read the accepted wallet statuses from admin_set_wallet_status.');
    for (const c of calls) {
      const statusExpr = (c[1].match(/p_status\s*:\s*([^,]*)/) || [])[1] || '';
      const literals = [...statusExpr.matchAll(/'([^']+)'/g)].map((x) => x[1]);
      if (!literals.length) fail('admin/app.js: admin_set_wallet_status must send p_status as string literals so they can be checked.');
      for (const value of literals) {
        if (!server.has(value)) fail(`admin/app.js sends wallet status '${value}'; admin_set_wallet_status accepts only: ${[...server].join(', ')}.`);
      }
      if (!/p_reason\s*:/.test(c[1])) fail('admin/app.js: admin_set_wallet_status must send p_reason (the server requires it).');
    }
  }
}

// ---------------------------------------------------------------------------
// (h) return shapes: keys the console reads vs keys the function produces
// ---------------------------------------------------------------------------

{
  // [rpc, where the result is consumed, variable holding one result object/row]
  const reads = [
    ['get_finance_settlement_batches', () => viewSource('settlements'), 'b'],
    ['finance_create_settlement_batch', () => viewSource('settlements'), 'r'],
    ['finance_cancel_settlement_batch', () => viewSource('settlements'), 'res'],
    ['get_finance_deposit_queue', () => functionSource('renderDeposits'), 'd'],
    ['review_wallet_deposit_request', () => functionSource('renderDeposits'), 'res'],
    ['admin_get_payment_destinations', () => viewSource('destinations'), 'd'],
    ['get_platform_commission_config', () => viewSource('commission'), 'conf'],
    ['get_notification_transport_status', () => viewSource('notifications'), 'st'],
    ['admin_ingest_card_vault_batch', () => viewSource('cards'), 'r'],
    ['admin_list_card_vault_metadata', () => viewSource('cards'), 'c'],
    ['finance_reconcile_wallets', () => functionSource('reconcileResultHtml'), 'w'],
  ];
  for (const [rpcName, sourceOf, variable] of reads) {
    const def = finalDefinition(rpcName);
    if (!def) { fail(`${rpcName} is not defined in the migrations (return-shape check).`); continue; }
    const source = sourceOf();
    // RETURNS TABLE(...) names the row keys exactly; a jsonb function builds them in its body.
    const produced = /returns\s+table/i.test(def.returns) ? def.returns : def.body;
    const keys = new Set([...source.matchAll(new RegExp(`(?<![\\w$.])${variable}\\.([a-z_][a-z0-9_]*)\\b(?!\\s*\\()`, 'g'))].map((x) => x[1]));
    if (!keys.size) { fail(`admin/app.js: no '${variable}.<key>' reads found for ${rpcName} — the return-shape scanner is out of date.`); continue; }
    for (const key of keys) {
      if (!new RegExp(`\\b${key}\\b`).test(produced)) {
        fail(`admin/app.js reads '${variable}.${key}' from ${rpcName}, but the final definition (${def.file}) never produces '${key}'.`);
      }
    }
  }
  // Dashboard cards are driven by label maps keyed by the returned JSON keys.
  for (const [rpcName, mapName] of [['admin_dashboard_kpis', 'KPI_LABELS'], ['get_commerce_admin_summary', 'COMM_LABELS']]) {
    const def = finalDefinition(rpcName);
    const map = app.match(new RegExp(`var\\s+${mapName}\\s*=\\s*\\{([\\s\\S]*?)\\};`));
    if (!def || !map) { fail(`Cannot compare ${mapName} with ${rpcName}.`); continue; }
    for (const x of map[1].matchAll(/([a-z_]+)\s*:/g)) {
      if (!def.body.includes(`'${x[1]}'`)) fail(`admin/app.js ${mapName} shows '${x[1]}', which ${rpcName} does not return.`);
    }
  }
}

// ---------------------------------------------------------------------------
// (i) direct table reads
// ---------------------------------------------------------------------------

{
  const allSql = migrationFiles.map((f) => stripSqlComments(readFileSync(path.join(migrationsDirectory, f), 'utf8'))).join('\n');
  const columnsOf = (table) => {
    const columns = new Set();
    const create = new RegExp(`create\\s+table\\s+(?:if\\s+not\\s+exists\\s+)?(?:public\\.)?${table}\\s*\\(`, 'gi');
    let m;
    while ((m = create.exec(allSql))) {
      const open = m.index + m[0].length - 1;
      let close;
      try { close = matchBracket(allSql, open); } catch { continue; }
      for (const part of splitTopLevel(allSql.slice(open + 1, close))) {
        const first = part.split(/\s+/)[0].toLowerCase().replace(/"/g, '');
        if (!/^(constraint|primary|unique|check|foreign|exclude|like)$/.test(first)) columns.add(first);
      }
    }
    const alter = new RegExp(`alter\\s+table\\s+(?:if\\s+exists\\s+)?(?:only\\s+)?(?:public\\.)?${table}\\b([^;]*);`, 'gi');
    while ((m = alter.exec(allSql))) {
      for (const x of m[1].matchAll(/add\s+column\s+(?:if\s+not\s+exists\s+)?"?([a-z_][a-z0-9_]*)/gi)) columns.add(x[1].toLowerCase());
    }
    return columns;
  };
  const selects = [];
  for (const x of app.matchAll(/\.from\(\s*'([a-z_]+)'\s*\)\s*\.select\(\s*'([^']*)'/g)) selects.push({ table: x[1], cols: x[2], index: x.index });
  for (const x of app.matchAll(/queryIn\(\s*'([a-z_]+)'\s*,\s*'([^']*)'\s*,\s*'([a-z_]+)'/g)) selects.push({ table: x[1], cols: `${x[2]}, ${x[3]}`, index: x.index });
  if ((app.match(/\.from\(/g) || []).length !== [...app.matchAll(/\.from\(\s*'[a-z_]+'\s*\)\s*\.select\(\s*'/g)].length + 1) {
    fail("admin/app.js: every direct table read must be written as db.from('table').select('literal columns') (or go through queryIn) so its columns can be checked.");
  }
  if (selects.length < 8) fail(`Only ${selects.length} direct table reads found in admin/app.js — the scanner is probably broken.`);
  for (const { table, cols, index } of selects) {
    const known = columnsOf(table);
    if (!known.size) { fail(`admin/app.js:${lineOf(app, index)}: table '${table}' is not created by any migration.`); continue; }
    const plain = cols.replace(/([a-z_]+)\(([^)]*)\)/g, (_, embedded, embeddedCols) => {
      const embeddedKnown = columnsOf(embedded);
      for (const c of embeddedCols.split(',').map((v) => v.trim()).filter(Boolean)) {
        if (!embeddedKnown.has(c)) fail(`admin/app.js:${lineOf(app, index)}: embedded column '${embedded}.${c}' does not exist in the migrations.`);
      }
      return '';
    });
    for (const c of plain.split(',').map((v) => v.trim()).filter(Boolean)) {
      if (c === '*') { fail(`admin/app.js:${lineOf(app, index)}: select('*') on '${table}' — name the columns (column-level grants may revoke some).`); continue; }
      if (!known.has(c)) fail(`admin/app.js:${lineOf(app, index)}: column '${table}.${c}' does not exist in the migrations.`);
    }
  }
  if (/compensation_model|compensation_rate_minor/.test(app)) {
    fail('admin/app.js references federated_plan_networks compensation columns, which are no longer selectable; use get_network_compensation_terms.');
  }
}

// ---------------------------------------------------------------------------
// (j) error codes raised by the RPCs the console calls
// ---------------------------------------------------------------------------

{
  const errTextSource = functionSource('errText');
  const known = [...errTextSource.matchAll(/^\s*([A-Z][A-Z0-9_]+)\s*:/gm)].map((x) => x[1]);
  if (known.length < 20) fail('admin/app.js: cannot read the known error codes from errText.');
  // Codes that only reach the console through a bug in the console itself, or that are handled where they occur.
  const handledElsewhere = new Set(['INVALID_ACTION']);
  const raised = new Map();
  for (const { name } of rpcCalls) {
    const def = finalDefinition(name.toLowerCase());
    if (!def) continue;
    for (const x of def.body.matchAll(/RAISE\s+EXCEPTION\s+'([A-Z][A-Z0-9_]+)/g)) {
      if (!raised.has(x[1])) raised.set(x[1], name);
    }
  }
  for (const [code, rpcName] of raised) {
    if (handledElsewhere.has(code)) continue;
    // errText matches by containment, in declaration order.
    if (!known.some((k) => code.includes(k))) {
      fail(`admin/app.js: errText has no message for '${code}' (raised by ${rpcName}); the user would only see the generic error.`);
    }
  }
  // A more specific code must be declared before a code it contains, or it is never reached.
  known.forEach((code, i) => {
    for (let j = 0; j < i; j += 1) {
      if (code !== known[j] && code.includes(known[j])) {
        fail(`admin/app.js: errText declares '${known[j]}' before '${code}'; containment matching makes '${code}' unreachable.`);
      }
    }
  });
}

// ---------------------------------------------------------------------------
// (k) CSP-safe markup and escaping
// ---------------------------------------------------------------------------

{
  const adminDirectory = path.join(repositoryRoot, 'admin');
  const index = readFileSync(path.join(adminDirectory, 'index.html'), 'utf8');
  for (const [label, source] of [['admin/index.html', index], ['admin/app.js', app]]) {
    const handler = source.match(/<[a-z][^<>]*\son[a-z]+\s*=\s*["']/i);
    if (handler) fail(`${label}: inline event handler attribute (${handler[0].slice(-30)}) — blocked by the CSP (script-src 'self'); bind it from app.js.`);
    if (/javascript\s*:/i.test(source)) fail(`${label}: javascript: URL.`);
  }
  for (const x of index.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)) {
    if (!/\ssrc=/.test(x[1]) || x[2].trim()) fail('admin/index.html: inline <script> — blocked by the CSP; move the code to app.js.');
  }
  if (/\beval\s*\(|new\s+Function\s*\(|setTimeout\(\s*['"`]|setInterval\(\s*['"`]|document\.write|\.outerHTML\s*=|insertAdjacentHTML/.test(app)) {
    fail('admin/app.js: eval / new Function / string timers / document.write / outerHTML / insertAdjacentHTML are not allowed.');
  }
  // esc() contains regex literals with quotes, which the bracket matcher cannot skip: cut it by indentation.
  const escMatch = app.match(/\n  (function esc\([\s\S]*?\n  \})\n/);
  const escSource = escMatch ? escMatch[1] : '';
  if (!escSource) fail('admin/app.js: function esc not found.');
  let escape = null;
  if (escSource) {
    try { escape = new Function(`return (${escSource});`)(); } catch (e) { fail(`esc() cannot be evaluated: ${e.message}`); }
  }
  if (escape) {
    const cases = [['&', '&amp;'], ['<', '&lt;'], ['>', '&gt;'], ['"', '&quot;'], ["'", '&#39;'], [null, ''], [undefined, ''], [0, '0'], ['&lt;', '&amp;lt;'],
      ['<img src=x onerror="a(\'1\')">&', '&lt;img src=x onerror=&quot;a(&#39;1&#39;)&quot;&gt;&amp;']];
    for (const [input, expected] of cases) {
      if (escape(input) !== expected) fail(`esc(${JSON.stringify(input)}) returned ${JSON.stringify(escape(input))}, expected ${JSON.stringify(expected)}.`);
    }
  }
  // Attribute values built from data must be double-quoted (esc() output is only safe inside quotes).
  const unquoted = app.match(/=\s*'\s*\+\s*esc\(/);
  if (unquoted) fail(`admin/app.js:${lineOf(app, unquoted.index)}: esc() value interpolated into an unquoted attribute.`);

  let vercel = null;
  try { vercel = JSON.parse(readFileSync(path.join(adminDirectory, 'vercel.json'), 'utf8')); } catch (e) { fail(`admin/vercel.json is not valid JSON: ${e.message}`); }
  if (vercel) {
    const rules = Array.isArray(vercel.headers) ? vercel.headers : [];
    if (!rules.length) fail('admin/vercel.json: "headers" must be a non-empty array.');
    let consoleCsp = null;
    for (const rule of rules) {
      if (typeof rule.source !== 'string' || !Array.isArray(rule.headers) || !rule.headers.length) { fail('admin/vercel.json: every headers entry needs { source, headers: [{ key, value }] }.'); continue; }
      try { new RegExp(`^${rule.source}$`); } catch (e) { fail(`admin/vercel.json: source ${rule.source} is not a valid pattern: ${e.message}`); }
      for (const h of rule.headers) {
        if (typeof h.key !== 'string' || typeof h.value !== 'string' || Object.keys(h).some((k) => k !== 'key' && k !== 'value')) fail(`admin/vercel.json: bad header entry ${JSON.stringify(h)}.`);
        if (h.key === 'Content-Security-Policy' && new RegExp(`^${rule.source}$`).test('/')) consoleCsp = h.value;
      }
    }
    if (!consoleCsp) fail('admin/vercel.json: no Content-Security-Policy applies to "/".');
    else {
      const directives = new Map(consoleCsp.split(';').map((d) => d.trim().split(/\s+/)).filter((d) => d[0]).map((d) => [d[0], d.slice(1)]));
      const script = directives.get('script-src') || [];
      if (script.includes("'unsafe-inline'") || script.includes("'unsafe-eval'") || script.includes('*')) fail("admin/vercel.json: script-src must not allow 'unsafe-inline', 'unsafe-eval' or *.");
      for (const x of index.matchAll(/<script\b[^>]*\ssrc="(https?:\/\/[^/"]+)/gi)) {
        if (!script.includes(x[1])) fail(`admin/vercel.json: script-src does not allow ${x[1]}, which index.html loads.`);
      }
      const connect = (directives.get('connect-src') || []).join(' ');
      if (!/https:\/\/\*\.supabase\.co/.test(connect)) fail('admin/vercel.json: connect-src must allow https://*.supabase.co (auth token exchange and RPC).');
      if (directives.has('navigate-to')) fail('admin/vercel.json: do not use navigate-to (it would block the Google OAuth redirect).');
      if (/\sstyle="/.test(index + app) && !(directives.get('style-src') || []).includes("'unsafe-inline'")) fail("admin/vercel.json: style-src needs 'unsafe-inline' while the console uses style attributes.");
      if (!directives.has('frame-ancestors') || !directives.has('base-uri') || !directives.has('object-src')) fail('admin/vercel.json: CSP must set frame-ancestors, base-uri and object-src.');
    }
  }
  // Login must stay a PKCE redirect back to the console origin.
  if (!/flowType\s*:\s*'pkce'/.test(app) || !/redirectTo\s*:\s*window\.location\.origin\b/.test(app)) {
    fail("admin/app.js: sign-in must use flowType 'pkce' and redirectTo: window.location.origin.");
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
