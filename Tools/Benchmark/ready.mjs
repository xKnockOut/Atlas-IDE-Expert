#!/usr/bin/env node
// Zeit bis „bereit“ mit mehreren Läufen je Fassung messen (#1479).
//
// Ohne IDE: startet je Fassung AtlasServer --check über eine Projektgruppe (derselbe Weg wie im Server: alle
// Projekte der .groupproj, gemeinsamer Index-Cache, Stufen) und liest die Zeit bis zum fertigen Index:
//   node Tools/Benchmark/ready.mjs --server vor=C:\alt\AtlasServer.exe --server nach=Output\Win64\Release\Bin\AtlasServer.exe
//     --target C:\Projekte\Gruppe --unit Haupt.dpr --runs 6 --cache %TEMP%\atlas-ready
// Aus der IDE: wertet die Diagnoselogs aus (eine Datei je IDE-Start), Fassung je Ordner:
//   node Tools/Benchmark/ready.mjs --logs vor=C:\Messung\vor --logs nach=C:\Messung\nach
// Ausgabe: Markdown-Tabelle mit Median und Spannweite; der erste Lauf je Fassung steht getrennt (Umstieg).

import { spawn } from 'node:child_process';
import { readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { performance } from 'node:perf_hooks';
import { readyFromLog, summarizeRuns, toMarkdown, checkIndexMs } from './ready-lib.mjs';

function parseArgs(argv) {
  const options = { servers: [], logs: [], runs: 6, target: '.', unit: null, cache: null, out: null };
  for (let i = 0; i < argv.length; i++) {
    const name = argv[i];
    const value = argv[i + 1];
    const pair = () => {
      const at = value.indexOf('=');
      return at > 0 ? { version: value.slice(0, at), path: value.slice(at + 1) } : { version: value, path: value };
    };
    if (name === '--server') options.servers.push(pair());
    else if (name === '--logs') options.logs.push(pair());
    else if (name === '--runs') options.runs = Number(value);
    else if (name === '--target') options.target = value;
    else if (name === '--unit') options.unit = value;
    else if (name === '--cache') options.cache = value;
    else if (name === '--out') options.out = value;
    else throw new Error(`Unbekannte Option ${name}`);
    i++;
  }
  return options;
}

function runCheck(server, options) {
  const args = ['--check', '.', '--rules', 'missing-begin-end', '--format', 'json', '--fail-on', 'never'];
  if (options.unit) args.push('--units', options.unit);
  if (options.cache) args.push('--index-cache', resolve(options.cache));
  return new Promise((done, fail) => {
    const started = performance.now();
    const proc = spawn(resolve(server), args, { cwd: resolve(options.target), stdio: ['ignore', 'ignore', 'pipe'] });
    let stderr = '';
    proc.stderr.on('data', (chunk) => { stderr += chunk; });
    proc.on('error', fail);
    proc.on('close', () => {
      const index = checkIndexMs(stderr);
      if (!index) fail(new Error(`Keine Zeile „Symbolindex“ von ${server}:\n${stderr}`));
      else done({ ...index, wallMs: performance.now() - started });
    });
  });
}

async function measureServers(options) {
  const runs = [];
  for (const { version, path } of options.servers) {
    for (let i = 1; i <= options.runs; i++) {
      const result = await runCheck(path, options);
      process.stderr.write(`${version} Lauf ${i}: ${result.units} Units in ${(result.ms / 1000).toFixed(1)} s\n`);
      runs.push({ version, ms: result.ms });
    }
  }
  return runs;
}

function logFiles(folder) {
  return readdirSync(folder)
    .filter((name) => /^diag-.*\.log$/i.test(name))
    .map((name) => join(folder, name))
    .sort((a, b) => statSync(a).mtimeMs - statSync(b).mtimeMs);
}

function measureLogs(options) {
  const runs = [];
  for (const { version, path } of options.logs) {
    for (const file of logFiles(path)) {
      const ready = readyFromLog(readFileSync(file, 'utf8'));
      if (!ready) {
        process.stderr.write(`${file}: kein fertiger Indexaufbau, übersprungen\n`);
        continue;
      }
      process.stderr.write(`${version} ${file}: ${ready.projects} Projekte, bereit nach ` +
        `${(ready.readyMs / 1000).toFixed(1)} s (ab Prozessstart ${(ready.fromProcessMs / 1000).toFixed(1)} s)` +
        `${ready.unfinished ? `, ${ready.unfinished} nicht fertig` : ''}${ready.cancelled ? ', mit Abbruch' : ''}\n`);
      runs.push({ version, ms: ready.readyMs, memMb: ready.memMb });
    }
  }
  return runs;
}

const options = parseArgs(process.argv.slice(2));
const runs = options.logs.length > 0 ? measureLogs(options) : await measureServers(options);
const report = toMarkdown(summarizeRuns(runs));
if (options.out) writeFileSync(options.out, report);
process.stdout.write(report);
