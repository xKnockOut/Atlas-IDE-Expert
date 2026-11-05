import test from 'node:test';
import assert from 'node:assert/strict';
import { timeOf, readyFromLog, median, summarizeRuns, toMarkdown, checkIndexMs } from './ready-lib.mjs';

const log = [
  '10:00:00.000 server start',
  '10:00:02.000 index project#0 start files 12 search 300 library 2000 cache write',
  '10:00:02.100 index project#1 start files 8 search 300 library 2000 cache write',
  '10:00:05.000 index project#0 projectStage 3000 ms parsed 0 cached 12 missing 0 mem 400 MB',
  '10:00:09.500 index project#0 done 7500 ms parsed 0 cached 2312 missing 0 units 2400 resolve 1 ms parse 0 ms mem 650 MB',
  '10:00:12.000 index project#1 done 9900 ms parsed 0 cached 2308 missing 0 units 2420 resolve 1 ms parse 0 ms mem 700 MB',
].join('\r\n');

test('timeOf liest die Zeit am Zeilenanfang', () => {
  assert.equal(timeOf('01:02:03.004 x'), 3723004);
  assert.equal(timeOf('kein Zeitstempel'), null);
});

test('readyFromLog: vom ersten Start bis zum letzten done', () => {
  const ready = readyFromLog(log);
  assert.equal(ready.projects, 2);
  assert.equal(ready.unfinished, 0);
  assert.equal(ready.readyMs, 10000);
  assert.equal(ready.fromProcessMs, 12000);
  assert.equal(ready.memMb, 700);
  assert.equal(ready.cancelled, false);
});

test('readyFromLog: abgebrochener Aufbau zählt nicht als fertig', () => {
  const ready = readyFromLog(log + '\n10:00:12.500 index project#1 done 100 ms parsed 0 cached 0 missing 0 units 1 ' +
    'resolve 0 ms parse 0 ms cancelled');
  assert.equal(ready.readyMs, 10000);
  assert.equal(ready.cancelled, true);
});

test('readyFromLog: über Mitternacht und ohne fertiges Projekt', () => {
  const ready = readyFromLog('23:59:59.000 index project#0 start\n00:00:04.000 index project#0 done 5000 ms');
  assert.equal(ready.readyMs, 5000);
  assert.equal(readyFromLog('10:00:00.000 index project#0 start'), null);
});

test('median gerade und ungerade', () => {
  assert.equal(median([3, 1, 2]), 2);
  assert.equal(median([4, 1, 3, 2]), 2.5);
  assert.ok(Number.isNaN(median([])));
});

test('summarizeRuns trennt den ersten Lauf je Fassung ab', () => {
  const rows = summarizeRuns([
    { version: 'vor', ms: 30000 }, { version: 'vor', ms: 4000 }, { version: 'vor', ms: 5000 },
    { version: 'nach', ms: 9000 }, { version: 'nach', ms: 3000 },
  ]);
  assert.deepEqual(rows.map((r) => [r.version, r.runs, r.firstMs, r.medianMs, r.minMs, r.maxMs]),
    [['vor', 2, 30000, 4500, 4000, 5000], ['nach', 1, 9000, 3000, 3000, 3000]]);
  assert.equal(summarizeRuns([{ version: 'x', ms: 1000 }])[0].firstMs, null);
});

test('toMarkdown mit Komma und Strich für fehlende Werte', () => {
  const text = toMarkdown(summarizeRuns([{ version: 'vor', ms: 17400, memMb: 190 }, { version: 'vor', ms: 17300, memMb: 188 }]));
  assert.match(text, /\| vor \| 1 \| 17,4 s \| 17,3 s \| 17,3–17,3 s \| 188 MB \|/);
});

test('checkIndexMs liest die stderr-Zeile von --check', () => {
  assert.deepEqual(checkIndexMs('Symbolindex: 3041 Units in 17,4 s\n'), { units: 3041, ms: 17400 });
  assert.deepEqual(checkIndexMs('Symbolindex: 786 Units in 0.7 s'), { units: 786, ms: 700 });
  assert.equal(checkIndexMs('nichts'), null);
});
