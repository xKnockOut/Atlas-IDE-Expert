// Reine Hilfsfunktionen der Benchmark-Suite (#85): Statistik, Zielwerte,
// Vergleich mit einer früheren Messung, Auswahl der Messpositionen.

export const TARGETS = {
  definition: 50,
  documentHighlight: 50,
  hover: 100,
  completion: 100,
  signatureHelp: 100,
  syntaxDiagnostics: 200,
  startupWithCache: 2000,
};

export function percentile(values, p) {
  if (values.length === 0) return NaN;
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[index];
}

export function summarize(values) {
  return {
    count: values.length,
    p50: round(percentile(values, 50)),
    p95: round(percentile(values, 95)),
    max: round(values.length ? Math.max(...values) : NaN),
  };
}

function round(value) {
  return Number.isFinite(value) ? Math.round(value * 10) / 10 : null;
}

// Zielwert gilt für p95; ein Vorgang ohne Messwerte gilt nicht als verfehlt.
export function checkTargets(results) {
  const misses = [];
  for (const [name, target] of Object.entries(TARGETS)) {
    const r = results[name];
    if (r && r.p95 !== null && r.p95 > target) misses.push({ name, target, p95: r.p95 });
  }
  return misses;
}

// Rückschritt: p95 mindestens um den Faktor langsamer und um mehr als die
// absolute Schwelle, damit Rauschen bei sehr kleinen Werten nicht anschlägt.
export function compare(current, previous, { factor = 1.2, minDeltaMs = 5 } = {}) {
  const rows = [];
  for (const name of Object.keys(TARGETS)) {
    const now = current[name]?.p95 ?? null;
    const before = previous?.[name]?.p95 ?? null;
    const regression = now !== null && before !== null && now > before * factor && now - before > minDeltaMs;
    rows.push({ name, before, now, regression });
  }
  return rows;
}

const KEYWORDS = new Set(('and array as asm begin case class const constructor destructor dispinterface div do downto else end ' +
  'except exports file finalization finally for function goto if implementation in inherited initialization inline ' +
  'interface is label library mod nil not object of or out packed procedure program property raise record repeat ' +
  'resourcestring set shl shr string then threadvar to try type unit until uses var while with xor').split(' '));

// Liefert bis zu Count Bezeichner-Positionen aus dem Implementierungsteil, gleichmäßig
// verteilt und damit bei gleichem Korpus immer dieselben.
export function samplePositions(text, count) {
  const lines = text.split(/\r?\n/);
  const start = lines.findIndex((l) => /^\s*implementation\b/i.test(l));
  const candidates = [];
  let inComment = false;
  for (let line = Math.max(0, start + 1); line < lines.length; line++) {
    const raw = lines[line];
    let code = '';
    for (let i = 0; i < raw.length; i++) {
      if (inComment) { if (raw[i] === '}') inComment = false; code += ' '; continue; }
      if (raw[i] === '{') { inComment = true; code += ' '; continue; }
      if (raw[i] === '/' && raw[i + 1] === '/') break;
      if (raw[i] === "'") { const end = raw.indexOf("'", i + 1); const stop = end < 0 ? raw.length : end; code += ' '.repeat(stop - i + 1); i = stop; continue; }
      code += raw[i];
    }
    for (const m of code.matchAll(/[A-Za-z_][A-Za-z0-9_]*/g)) {
      if (!KEYWORDS.has(m[0].toLowerCase())) candidates.push({ line, character: m.index + 1, name: m[0] });
    }
  }
  if (candidates.length <= count) return candidates;
  const step = candidates.length / count;
  return Array.from({ length: count }, (_, i) => candidates[Math.floor(i * step)]);
}

/// Positionen für die Vervollständigung (#31): zwei getippte Zeichen, damit wie im Editor auch Symbole
/// aus nicht eingebundenen Units (#180) und die unscharfe Auswahl (#229) mitlaufen.
export function completionPositions(positions) {
  return positions.map((p) => (p.name.length >= 2 ? { ...p, character: p.character + 1 } : p));
}

export function toMarkdown(report, comparison, misses) {
  const out = [];
  out.push(`# Benchmark ${report.version ?? ''}`.trim(), '');
  out.push(`Gemessen ${report.date} mit ${report.corpus.files} Dateien (${report.corpus.roots.join(', ')}).`, '');
  out.push('| Vorgang | Ziel (ms) | p50 | p95 | max | n | vorher p95 | Bewertung |');
  out.push('|---|---|---|---|---|---|---|---|');
  for (const [name, target] of Object.entries(TARGETS)) {
    const r = report.results[name] ?? { p50: null, p95: null, max: null, count: 0 };
    const c = comparison.find((x) => x.name === name);
    const miss = misses.some((m) => m.name === name);
    const verdict = r.count === 0 ? 'nicht gemessen' : miss ? 'Ziel verfehlt' : c?.regression ? 'Rückschritt' : 'ok';
    out.push(`| ${name} | ${target} | ${fmt(r.p50)} | ${fmt(r.p95)} | ${fmt(r.max)} | ${r.count} | ${fmt(c?.before)} | ${verdict} |`);
  }
  return out.join('\n') + '\n';
}

function fmt(value) {
  return value === null || value === undefined ? '–' : String(value);
}
