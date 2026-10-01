import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.dirname(scriptDirectory);
const templateRoot = path.join(repositoryRoot, 'legal');
const outputDirectory = path.resolve(
  process.argv[2] || path.join(repositoryRoot, 'build', 'web', 'legal'),
);

function requiredEnvironment(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`HOLD: Missing required environment variable ${name}.`);
  return value;
}

function httpsOrigin(value, label) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error(`HOLD: ${label} must be an absolute URL.`);
  }

  if (
    url.protocol !== 'https:' ||
    ['localhost', '127.0.0.1'].includes(url.hostname) ||
    url.search ||
    url.hash
  ) {
    throw new Error(
      `HOLD: ${label} must be a non-local HTTPS URL without query or fragment.`,
    );
  }

  return url.origin;
}

const publicOrigin = httpsOrigin(
  requiredEnvironment('ADMIN_PUBLIC_ORIGIN'),
  'Public legal origin',
);
const supabaseUrl = httpsOrigin(
  requiredEnvironment('SUPABASE_URL'),
  'Supabase URL',
);
const publishableKey = requiredEnvironment('SUPABASE_PUBLISHABLE_KEY');

if (!publishableKey.startsWith('sb_publishable_') && !publishableKey.startsWith('eyJ')) {
  throw new Error(
    'HOLD: Supabase publishable key is not a client-safe publishable or legacy anon key.',
  );
}

const replacements = new Map([
  ['{{PUBLIC_ORIGIN}}', publicOrigin],
  ['{{SUPABASE_URL}}', supabaseUrl],
  ['{{SUPABASE_URL_JSON}}', JSON.stringify(supabaseUrl)],
  ['{{SUPABASE_PUBLISHABLE_KEY_JSON}}', JSON.stringify(publishableKey)],
]);

await mkdir(outputDirectory, { recursive: true });

const artifacts = [
  ['privacy.template.html', 'privacy.html'],
  ['delete-account.template.html', 'delete-account.html'],
  ['delete-account.template.js', 'delete-account.js'],
];

for (const [templateName, outputName] of artifacts) {
  const templatePath = path.join(templateRoot, templateName);
  let content = await readFile(templatePath, 'utf8');
  for (const [token, replacement] of replacements) {
    content = content.replaceAll(token, replacement);
  }

  if (/\{\{[A-Z0-9_]+\}\}/.test(content)) {
    throw new Error(`HOLD: Unresolved public legal placeholder in ${outputName}.`);
  }
  if (/service[_-]?role/i.test(content)) {
    throw new Error(
      `HOLD: A service-role reference reached the public legal artifact ${outputName}.`,
    );
  }

  await writeFile(path.join(outputDirectory, outputName), content, 'utf8');
}

console.log('WASEL NET PUBLIC LEGAL ARTIFACT: PASS');
console.log(`Output: ${outputDirectory}`);
