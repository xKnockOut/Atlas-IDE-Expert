// Reine Hilfsfunktionen für die Messung der Zeit bis „bereit“ (#1479): Zeilen „index project#N …“ aus dem
// anonymen Diagnoselog lesen, Läufe je Fassung zusammenfassen (Median, Spannweite) und als Markdown-Tabelle
// ausgeben. Der erste Lauf einer Fassung steht getrennt („Umstieg“): Er liest noch die Caches der vorigen.

/** Millisekunden seit Mitternacht aus „hh:nn:ss.zzz“ am Zeilenanfang; null ohne Zeit. */
export function timeOf(line) {
  const m = /^(\d{2}):(\d{2}):(\d{2})\.(\d{3})\b/.exec(line);
  if (!m) return null;
  return ((Number(m[1]) * 60 + Number(m[2])) * 60 + Number(m[3])) * 1000 + Number(m[4]);
}

/**
 * Wertet ein Diagnoselog aus (eine Datei je Serverprozess). Ergebnis: Projekte, Zeit vom ersten Indexstart
 * bis zum letzten „done“ (bereit) und vom ersten Eintrag der Datei an, größter „mem“-Wert der Index-Zeilen und
 * ob ein Aufbau abgebrochen wurde. null, wenn kein Projekt fertig wurde.
 */
export function readyFromLog(text) {
  const projects = new Map();
  let firstLine = null;
  let firstStart = null;
  let lastDone = null;
  let memMb = 0;
  let cancelled = false;
  let previous = null;
  let dayOffset = 0;
  for (const line of text.split(/\r?\n/)) {
    let t = timeOf(line);
    if (t === null) continue;
    // Über Mitternacht weiterzählen.
    if (previous !== null && t + dayOffset < previous - 12 * 3600 * 1000) dayOffset += 24 * 3600 * 1000;
    t += dayOffset;
    previous = t;
    if (firstLine === null) firstLine = t;
    const m = /index project#(\d+) (start|done|projectStage|cacheWrite)\b/.exec(line);
    if (!m) continue;
    const mem = /\bmem (\d+) MB/.exec(line);
    if (mem) memMb = Math.max(memMb, Number(mem[1]));
    const id = Number(m[1]);
    if (m[2] === 'start') {
      if (firstStart === null) firstStart = t;
      if (!projects.has(id)) projects.set(id, null);
    } else if (m[2] === 'done') {
      if (/\bcancelled\b/.test(line)) {
        cancelled = true;
        continue;
      }
      projects.set(id, t);
      lastDone = t;
    }
  }
  if (lastDone === null || firstStart === null) return null;
  const open = [...projects.values()].filter((v) => v === null).length;
  return {
    projects: projects.size,
    unfinished: open,
    readyMs: lastDone - firstStart,
    fromProcessMs: lastDone - firstLine,
    memMb,
    cancelled,
  };
}

/** Median einer Zahlenliste; NaN ohne Werte. */
export function median(values) {
  if (values.length === 0) return NaN;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/**
 * Fasst Läufe zusammen: runs = [{ version, ms, memMb? }] in Messreihenfolge. Je Fassung zählt der erste Lauf
 * als Umstieg und geht nicht in Median und Spannweite ein, solange danach noch mindestens ein Lauf folgt.
 */
export function summarizeRuns(runs) {
  const byVersion = new Map();
  for (const run of runs) {
    if (!byVersion.has(run.version)) byVersion.set(run.version, []);
    byVersion.get(run.version).push(run);
  }
  const rows = [];
  for (const [version, list] of byVersion) {
    const first = list.length > 1 ? list[0] : null;
    const rest = list.length > 1 ? list.slice(1) : list;
    const ms = rest.map((r) => r.ms);
    const mem = rest.map((r) => r.memMb).filter((v) => typeof v === 'number');
    rows.push({
      version,
      runs: rest.length,
      firstMs: first ? first.ms : null,
      medianMs: median(ms),
      minMs: Math.min(...ms),
      maxMs: Math.max(...ms),
      medianMemMb: mem.length ? median(mem) : null,
    });
  }
  return rows;
}

function seconds(ms) {
  return ms === null || Number.isNaN(ms) ? '–' : (ms / 1000).toFixed(1).replace('.', ',');
}

/** Markdown-Tabelle zu summarizeRuns. */
export function toMarkdown(rows) {
  const lines = [
    '| Fassung | Läufe | Umstieg (1. Lauf) | Median | Spannweite | Speicher (Median) |',
    '|---|---:|---:|---:|---:|---:|',
  ];
  for (const r of rows) {
    const mem = r.medianMemMb === null ? '–' : `${Math.round(r.medianMemMb)} MB`;
    lines.push(`| ${r.version} | ${r.runs} | ${seconds(r.firstMs)} s | ${seconds(r.medianMs)} s | ` +
      `${seconds(r.minMs)}–${seconds(r.maxMs)} s | ${mem} |`);
  }
  return lines.join('\n') + '\n';
}

/** Zeit aus der stderr-Zeile von --check („Symbolindex: 3041 Units in 17,4 s“); null ohne Zeile. */
export function checkIndexMs(stderr) {
  const m = /Symbolindex: (\d+) Units in (\d+)[.,](\d) s/.exec(stderr);
  if (!m) return null;
  return { units: Number(m[1]), ms: Number(m[2]) * 1000 + Number(m[3]) * 100 };
}
