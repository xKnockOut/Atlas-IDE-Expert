#!/usr/bin/env node
// Benchmark-Suite für die Leistungs-Zielwerte (#85). Startet den echten Server
// über stdio, misst die Antwortzeiten auf einem festen Korpus und schreibt einen
// Bericht (JSON und Markdown). Mit --baseline wird mit einer früheren Messung
// verglichen; Exit-Code 1 bei verfehltem Zielwert oder Rückschritt.
//
//   node Tools/Benchmark/bench.mjs --server Output\Win64\Release\Bin\BetterDelphiLSP.exe
//     [--corpus Tests/Referenzprojekt] [--corpus "C:\Program Files (x86)\Embarcadero\Studio\37.0\source\vcl"]
//     [--samples 30] [--out benchmark] [--baseline benchmark/letzte.json] [--no-fail]

import { spawn } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, resolve, extname } from 'node:path';
import { pathToFileURL } from 'node:url';
import { performance } from 'node:perf_hooks';
import { summarize, checkTargets, compare, samplePositions, toMarkdown } from './lib.mjs';

const args = parseArgs(process.argv.slice(2));
const repoRoot = resolve(new URL('../..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const server = args.server ?? join(repoRoot, 'Output', 'Win64', 'Release', 'Bin', 'BetterDelphiLSP.exe');
const corpus = (args.corpus.length ? args.corpus : [join(repoRoot, 'Tests', 'Referenzprojekt')]).map((c) => resolve(c));
const samples = Number(args.samples ?? 30);
const outDir = resolve(args.out ?? join(repoRoot, 'benchmark'));

class LspClient {
  constructor(command, cwd) {
    this.proc = spawn(command, [], { cwd, stdio: ['pipe', 'pipe', 'inherit'] });
    this.buffer = Buffer.alloc(0);
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = [];
    this.proc.stdout.on('data', (chunk) => this.onData(chunk));
    this.exited = new Promise((r) => this.proc.on('exit', r));
  }

  onData(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    for (;;) {
      const headerEnd = this.buffer.indexOf('\r\n\r\n');
      if (headerEnd < 0) return;
      const match = /Content-Length:\s*(\d+)/i.exec(this.buffer.subarray(0, headerEnd).toString('ascii'));
      const length = Number(match?.[1] ?? 0);
      if (this.buffer.length < headerEnd + 4 + length) return;
      const message = JSON.parse(this.buffer.subarray(headerEnd + 4, headerEnd + 4 + length).toString('utf8'));
      this.buffer = this.buffer.subarray(headerEnd + 4 + length);
      this.dispatch(message);
    }
  }

  dispatch(message) {
    if (message.id !== undefined && message.method === undefined) {
      const p = this.pending.get(message.id);
      this.pending.delete(message.id);
      if (p) message.error ? p.reject(new Error(message.error.message)) : p.resolve(message.result);
    } else if (message.id !== undefined) {
      this.write({ jsonrpc: '2.0', id: message.id, result: null });
    } else {
      for (const l of [...this.listeners]) l(message);
    }
  }

  write(message) {
    const body = Buffer.from(JSON.stringify(message), 'utf8');
    this.proc.stdin.write(`Content-Length: ${body.length}\r\n\r\n`);
    this.proc.stdin.write(body);
  }

  request(method, params) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.write({ jsonrpc: '2.0', id, method, params });
    });
  }

  notify(method, params) {
    this.write({ jsonrpc: '2.0', method, params });
  }

  waitFor(predicate, timeoutMs) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { remove(); reject(new Error('Zeitüberschreitung')); }, timeoutMs);
      const listener = (m) => { if (predicate(m)) { remove(); resolve(m); } };
      const remove = () => { clearTimeout(timer); this.listeners = this.listeners.filter((l) => l !== listener); };
      this.listeners.push(listener);
    });
  }

  async shutdown() {
    await this.request('shutdown', null).catch(() => {});
    this.notify('exit', null);
    await Promise.race([this.exited, new Promise((r) => setTimeout(r, 5000))]);
    this.proc.kill();
  }
}

async function start(root, symbolProbe) {
  const begin = performance.now();
  const client = new LspClient(server, root);
  await client.request('initialize', {
    processId: process.pid,
    rootUri: pathToFileURL(root).href,
    workspaceFolders: [{ uri: pathToFileURL(root).href, name: 'korpus' }],
    capabilities: { textDocument: { hover: { contentFormat: ['markdown', 'plaintext'] } } },
  });
  client.notify('initialized', {});
  // Bereit ist der Server, sobald die Symbolsuche ein bekanntes Symbol findet.
  for (;;) {
    const found = await client.request('workspace/symbol', { query: symbolProbe });
    if (Array.isArray(found) && found.length > 0) break;
    if (performance.now() - begin > 120000) throw new Error('Index nicht innerhalb von 120 s bereit');
    await new Promise((r) => setTimeout(r, 20));
  }
  return { client, ms: performance.now() - begin };
}

async function timed(fn) {
  const t = performance.now();
  await fn();
  return performance.now() - t;
}

function listSources(root) {
  const files = [];
  const walk = (dir) => {
    for (const name of readdirSync(dir)) {
      const full = join(dir, name);
      if (statSync(full).isDirectory()) walk(full);
      else if (['.pas', '.dpr', '.dpk'].includes(extname(name).toLowerCase())) files.push(full);
    }
  };
  walk(root);
  return files.sort();
}

async function main() {
  if (!existsSync(server)) throw new Error(`Server nicht gefunden: ${server}`);
  const files = corpus.flatMap(listSources);
  if (files.length === 0) throw new Error('Korpus enthält keine Quelltexte');
  const root = corpus[0];
  const positions = files.flatMap((file) => {
    const text = readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
    return samplePositions(text, Math.max(1, Math.ceil(samples / files.length))).map((p) => ({ ...p, file, text }));
  }).slice(0, samples);
  const probe = positions[0]?.name ?? 'T';

  const results = {};
  const cold = await start(root, probe);
  results.startupColdCache = summarize([cold.ms]);
  await cold.client.shutdown();

  const startups = [];
  let session = null;
  for (let i = 0; i < 3; i++) {
    if (session) await session.client.shutdown();
    session = await start(root, probe);
    startups.push(session.ms);
  }
  results.startupWithCache = summarize(startups);
  const client = session.client;

  const timings = { definition: [], documentHighlight: [], hover: [], completion: [], signatureHelp: [], syntaxDiagnostics: [] };
  const opened = new Set();
  for (const p of positions) {
    const uri = pathToFileURL(p.file).href;
    if (!opened.has(uri)) {
      client.notify('textDocument/didOpen', { textDocument: { uri, languageId: 'delphi', version: 1, text: p.text } });
      opened.add(uri);
    }
    const params = { textDocument: { uri }, position: { line: p.line, character: p.character } };
    timings.definition.push(await timed(() => client.request('textDocument/definition', params)));
    timings.documentHighlight.push(await timed(() => client.request('textDocument/documentHighlight', params)));
    timings.hover.push(await timed(() => client.request('textDocument/hover', params)));
    timings.completion.push(await timed(() => client.request('textDocument/completion', params)));
    timings.signatureHelp.push(await timed(() => client.request('textDocument/signatureHelp', params)));
  }

  // Syntaxfehler nach Tastendruck: ein Zeichen einfügen, das die Zeile kaputt macht,
  // und die Zeit bis zu den Diagnosen genau dieser Version messen.
  let version = 1;
  for (const p of positions.slice(0, Math.min(10, positions.length))) {
    const uri = pathToFileURL(p.file).href;
    for (const text of [p.text.replace(/\bbegin\b/i, 'begin )'), p.text]) {
      version++;
      const wanted = version;
      const arrived = client.waitFor((m) => m.method === 'textDocument/publishDiagnostics' && m.params.uri === uri &&
        (m.params.version === undefined || m.params.version === wanted), 10000);
      const t = performance.now();
      client.notify('textDocument/didChange', { textDocument: { uri, version: wanted }, contentChanges: [{ text }] });
      await arrived;
      if (text !== p.text) timings.syntaxDiagnostics.push(performance.now() - t);
    }
  }
  await client.shutdown();

  for (const [name, values] of Object.entries(timings)) results[name] = summarize(values);
  const report = {
    date: new Date().toISOString(),
    version: args.version ?? null,
    server,
    corpus: { roots: corpus, files: files.length, positions: positions.length },
    results,
  };
  const previous = args.baseline && existsSync(args.baseline) ? JSON.parse(readFileSync(args.baseline, 'utf8')).results : null;
  const comparison = compare(results, previous);
  const misses = checkTargets(results);
  const markdown = toMarkdown(report, comparison, misses);

  mkdirSync(outDir, { recursive: true });
  const stamp = report.date.replace(/[:.]/g, '-');
  writeFileSync(join(outDir, `benchmark-${stamp}.json`), JSON.stringify(report, null, 2));
  writeFileSync(join(outDir, 'letzte.json'), JSON.stringify(report, null, 2));
  writeFileSync(join(outDir, 'bericht.md'), markdown);
  process.stderr.write(markdown);

  const regressions = comparison.filter((c) => c.regression);
  if (!args.noFail && (misses.length > 0 || regressions.length > 0)) process.exitCode = 1;
}

function parseArgs(list) {
  const result = { corpus: [] };
  for (let i = 0; i < list.length; i++) {
    const [key, inline] = list[i].split(/=(.*)/s);
    const value = () => inline ?? list[++i];
    switch (key) {
      case '--server': result.server = value(); break;
      case '--corpus': result.corpus.push(value()); break;
      case '--samples': result.samples = value(); break;
      case '--out': result.out = value(); break;
      case '--baseline': result.baseline = value(); break;
      case '--version': result.version = value(); break;
      case '--no-fail': result.noFail = true; break;
      default: throw new Error(`Unbekanntes Argument: ${list[i]}`);
    }
  }
  return result;
}

main().catch((e) => { process.stderr.write(`${e.message}\n`); process.exitCode = 2; });
