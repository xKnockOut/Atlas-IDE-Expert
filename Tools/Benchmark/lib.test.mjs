import test from 'node:test';
import assert from 'node:assert/strict';
import { percentile, summarize, checkTargets, compare, samplePositions, completionPositions, toMarkdown } from './lib.mjs';

test('percentile und summarize', () => {
  const v = [5, 1, 4, 2, 3, 6, 7, 8, 9, 10];
  assert.equal(percentile(v, 50), 5);
  assert.equal(percentile(v, 95), 10);
  assert.deepEqual(summarize([]), { count: 0, p50: null, p95: null, max: null });
});

test('checkTargets meldet nur verfehlte p95', () => {
  const misses = checkTargets({ definition: { p95: 60 }, hover: { p95: 90 }, completion: { p95: null } });
  assert.deepEqual(misses.map((m) => m.name), ['definition']);
});

test('compare erkennt Rückschritte, ignoriert Rauschen', () => {
  const rows = compare({ definition: { p95: 20 }, hover: { p95: 4 } }, { definition: { p95: 10 }, hover: { p95: 2 } });
  assert.equal(rows.find((r) => r.name === 'definition').regression, true);
  assert.equal(rows.find((r) => r.name === 'hover').regression, false);
  assert.equal(compare({ hover: { p95: 4 } }, null).every((r) => !r.regression), true);
});

test('samplePositions überspringt Interface, Kommentare, Strings und Schlüsselwörter', () => {
  const text = 'unit A;\ninterface\nprocedure Foo;\nimplementation\n{ Bar }\nprocedure Foo;\nbegin\n  Writeln(\'Baz\'); // Qux\nend;\nend.';
  const names = samplePositions(text, 10).map((p) => p.name);
  assert.deepEqual(names, ['Foo', 'Writeln']);
  const p = samplePositions(text, 10)[1];
  assert.equal(p.line, 7);
  assert.equal(p.character, 3);
});

test('samplePositions verteilt gleichmäßig', () => {
  const body = Array.from({ length: 100 }, (_, i) => `  X${i};`).join('\n');
  const picked = samplePositions(`implementation\n${body}`, 10);
  assert.equal(picked.length, 10);
  assert.equal(picked[1].name, 'X10');
});

test('toMarkdown bewertet', () => {
  const md = toMarkdown({ date: 'd', corpus: { files: 1, roots: ['r'] }, results: { definition: { p50: 1, p95: 70, max: 80, count: 3 } } },
    compare({ definition: { p95: 70 } }, null), checkTargets({ definition: { p95: 70 } }));
  assert.match(md, /\| definition \| 50 \| 1 \| 70 \| 80 \| 3 \| – \| Ziel verfehlt \|/);
  assert.match(md, /\| hover \| 100 .* nicht gemessen \|/);
});

test('completionPositions setzt den Cursor hinter zwei Zeichen', () => {
  const moved = completionPositions([{ line: 1, character: 3, name: 'Writeln' }, { line: 2, character: 5, name: 'I' }]);
  assert.equal(moved[0].character, 4);
  assert.equal(moved[1].character, 5);
});
