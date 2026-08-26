import process from 'node:process';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const privacyPath = '/legal/privacy.html';
const deletionPath = '/legal/delete-account.html';
const deletionScriptPath = '/legal/delete-account.js';

function hold(message) {
  throw new Error(`HOLD: ${message}`);
}

export function normalizePublicOrigin(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    hold('Admin public origin must be an absolute URL.');
  }

  if (
    url.protocol !== 'https:' ||
    url.username ||
    url.password ||
    url.pathname !== '/' ||
    url.search ||
    url.hash ||
    ['localhost', '127.0.0.1', '::1'].includes(url.hostname)
  ) {
    hold(
      'Admin public origin must be a non-local HTTPS origin without credentials, path, query, or fragment.',
    );
  }

  if (url.hostname.endsWith('.supabase.co')) {
    hold('Supabase shared-domain endpoints are not an approved public legal host.');
  }

  return url.origin;
}

function assertHeaderIncludes(response, name, expected, label) {
  const actual = response.headers.get(name)?.toLowerCase() || '';
  if (!actual.includes(expected.toLowerCase())) {
    hold(`${label} must return ${name}: ${expected}.`);
  }
}

function assertFrameDenied(response, label) {
  const frameOptions = response.headers.get('x-frame-options')?.toLowerCase() || '';
  const csp = response.headers.get('content-security-policy')?.toLowerCase() || '';
  if (frameOptions !== 'deny' && !csp.includes("frame-ancestors 'none'")) {
    hold(`${label} must deny framing with X-Frame-Options or CSP.`);
  }
}

export async function verifyHtmlResponse(response, {
  label,
  expectedText,
  expectedLink,
  expectedScript = null,
}) {
  if (response.status !== 200) hold(`${label} returned HTTP ${response.status}.`);
  assertHeaderIncludes(response, 'content-type', 'text/html', label);
  assertHeaderIncludes(response, 'x-content-type-options', 'nosniff', label);
  assertFrameDenied(response, label);

  const body = await response.text();
  const cspHeader = response.headers.get('content-security-policy') || '';
  if (
    !cspHeader &&
    !body.toLowerCase().includes('http-equiv="content-security-policy"')
  ) {
    hold(`${label} is missing its Content Security Policy.`);
  }
  if (!body.includes(expectedText)) hold(`${label} is missing its expected Arabic title.`);
  if (!body.includes(`href="${expectedLink}"`)) {
    hold(`${label} is missing its reciprocal HTTPS legal link.`);
  }
  if (expectedScript && !body.includes(`src="${expectedScript}"`)) {
    hold(`${label} is missing the account-deletion client script.`);
  }
  if (/\{\{[A-Z0-9_]+\}\}/.test(body)) hold(`${label} contains an unresolved placeholder.`);
  if (/service[_-]?role/i.test(body)) hold(`${label} exposes a service-role reference.`);
}

export async function verifyScriptResponse(response) {
  const label = 'Account-deletion script';
  if (response.status !== 200) hold(`${label} returned HTTP ${response.status}.`);

  const contentType = response.headers.get('content-type')?.toLowerCase() || '';
  if (!contentType.includes('javascript')) {
    hold(`${label} must return a JavaScript content type.`);
  }
  assertHeaderIncludes(response, 'x-content-type-options', 'nosniff', label);

  const body = await response.text();
  for (const expected of [
    'request_my_account_deletion',
    '/auth/v1/token?grant_type=password',
    '/auth/v1/logout',
  ]) {
    if (!body.includes(expected)) hold(`${label} is missing ${expected}.`);
  }
  if (/\{\{[A-Z0-9_]+\}\}/.test(body)) hold(`${label} contains an unresolved placeholder.`);
  if (/service[_-]?role/i.test(body)) hold(`${label} exposes a service-role reference.`);
}

async function fetchExact(url, fetchImpl) {
  try {
    return await fetchImpl(url, {
      redirect: 'error',
      signal: AbortSignal.timeout(15_000),
      headers: { accept: 'text/html,application/javascript;q=0.9' },
    });
  } catch (error) {
    hold(`Could not fetch ${url}: ${error instanceof Error ? error.message : 'request failed'}.`);
  }
}

export async function verifyHostedLegalPages(originValue, fetchImpl = fetch) {
  const origin = normalizePublicOrigin(originValue);
  const privacyUrl = `${origin}${privacyPath}`;
  const deletionUrl = `${origin}${deletionPath}`;
  const deletionScriptUrl = `${origin}${deletionScriptPath}`;

  const [privacyResponse, deletionResponse, scriptResponse] = await Promise.all([
    fetchExact(privacyUrl, fetchImpl),
    fetchExact(deletionUrl, fetchImpl),
    fetchExact(deletionScriptUrl, fetchImpl),
  ]);

  await verifyHtmlResponse(privacyResponse, {
    label: 'Privacy page',
    expectedText: 'سياسة خصوصية واصل نت',
    expectedLink: deletionUrl,
  });
  await verifyHtmlResponse(deletionResponse, {
    label: 'Account-deletion page',
    expectedText: 'طلب حذف حساب واصل نت',
    expectedLink: privacyUrl,
    expectedScript: 'delete-account.js',
  });
  await verifyScriptResponse(scriptResponse);

  return { origin, privacyUrl, deletionUrl, deletionScriptUrl };
}

function fixtureResponse(body, contentType, extraHeaders = {}) {
  return new Response(body, {
    status: 200,
    headers: {
      'content-type': contentType,
      'x-content-type-options': 'nosniff',
      'x-frame-options': 'DENY',
      ...extraHeaders,
    },
  });
}

async function runSelfTest() {
  const origin = 'https://admin.example.com';
  const fixtures = new Map([
    [`${origin}${privacyPath}`, fixtureResponse(
      `<meta http-equiv="Content-Security-Policy"><h1>سياسة خصوصية واصل نت</h1><a href="${origin}${deletionPath}">حذف الحساب</a>`,
      'text/html; charset=utf-8',
    )],
    [`${origin}${deletionPath}`, fixtureResponse(
      `<meta http-equiv="Content-Security-Policy"><h1>طلب حذف حساب واصل نت</h1><a href="${origin}${privacyPath}">الخصوصية</a><script src="delete-account.js"></script>`,
      'text/html; charset=utf-8',
    )],
    [`${origin}${deletionScriptPath}`, fixtureResponse(
      "request_my_account_deletion /auth/v1/token?grant_type=password /auth/v1/logout",
      'application/javascript; charset=utf-8',
    )],
  ]);
  const fixtureFetch = async (url) => {
    const fixture = fixtures.get(url);
    if (!fixture) return new Response('', { status: 404 });
    return fixture.clone();
  };

  await verifyHostedLegalPages(origin, fixtureFetch);

  let rejectedUnsafeOrigin = false;
  try {
    normalizePublicOrigin('https://example.supabase.co');
  } catch (error) {
    rejectedUnsafeOrigin = error instanceof Error && error.message.startsWith('HOLD:');
  }
  if (!rejectedUnsafeOrigin) throw new Error('Self-test failed to reject a Supabase shared domain.');

  let rejectedWrongMime = false;
  try {
    await verifyHtmlResponse(
      fixtureResponse('سياسة خصوصية واصل نت', 'text/plain'),
      {
        label: 'Fixture page',
        expectedText: 'سياسة خصوصية واصل نت',
        expectedLink: `${origin}${deletionPath}`,
      },
    );
  } catch (error) {
    rejectedWrongMime = error instanceof Error && error.message.startsWith('HOLD:');
  }
  if (!rejectedWrongMime) throw new Error('Self-test failed to reject text/plain HTML.');

  console.log('WASEL NET HOSTED LEGAL VERIFIER SELF-TEST: PASS');
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;

if (isMain) {
  try {
    if (process.argv[2] === '--self-test') {
      await runSelfTest();
    } else {
      const origin = process.argv[2] || process.env.ADMIN_PUBLIC_ORIGIN;
      if (!origin) hold('Pass the hosted admin origin as the first argument or ADMIN_PUBLIC_ORIGIN.');
      const result = await verifyHostedLegalPages(origin);
      console.log('WASEL NET HOSTED PUBLIC LEGAL VERIFICATION: PASS');
      console.log(`Privacy: ${result.privacyUrl}`);
      console.log(`Account deletion: ${result.deletionUrl}`);
    }
  } catch (error) {
    console.error(error instanceof Error ? error.message : 'HOLD: Unknown verification failure.');
    process.exitCode = 1;
  }
}
