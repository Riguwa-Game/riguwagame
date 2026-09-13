// Guards the "English only" rule. Scans every source file for CJK characters.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
// CJK ideographs, plus the full-width punctuation the original UI text used.
const CJK = /[　-〿㐀-䶿一-鿿！-｠]/u;

function sourceFiles(dir, out = []) {
  for (const name of readdirSync(dir)) {
    if (name === 'vendor' || name === 'node_modules' || name === 'test' || name === 'public') continue;
    const p = join(dir, name);
    if (statSync(p).isDirectory()) sourceFiles(p, out);
    else if (/\.(js|html|css|md)$/.test(name)) out.push(p);
  }
  return out;
}

test('no CJK characters remain in game source', () => {
  const offenders = [];
  for (const file of sourceFiles(ROOT)) {
    const lines = readFileSync(file, 'utf8').split('\n');
    lines.forEach((line, i) => {
      if (CJK.test(line)) offenders.push(`${file.slice(ROOT.length + 1)}:${i + 1}`);
    });
  }
  assert.deepEqual(offenders, [], `CJK text found at:\n  ${offenders.join('\n  ')}`);
});

test('index.html declares English', () => {
  const html = readFileSync(join(ROOT, 'index.html'), 'utf8');
  assert.match(html, /<html lang="en">/, 'index.html must declare lang="en"');
  assert.match(html, /<title>Doodle District<\/title>/, 'title must be "Doodle District"');
});

test('the import map still points at vendored libraries, not a CDN', () => {
  const html = readFileSync(join(ROOT, 'index.html'), 'utf8');
  assert.match(html, /"three":\s*"\.\/vendor\/three\/three\.module\.js"/, 'three must be vendored');
  assert.match(html, /src="\.\/vendor\/peerjs\/peerjs\.min\.js"/, 'peerjs must be vendored');
  assert.doesNotMatch(html, /cdn\.jsdelivr\.net/, 'no CDN dependencies');
});
