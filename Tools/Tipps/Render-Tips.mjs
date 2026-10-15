// Erzeugt die Bilder der Karte „Atlas entdecken“ (#757) aus den HTML-Vorlagen in Tools/Tipps/Vorlagen.
//
// Je Vorlage <name>.html entstehen Setup/Tipps/<name>.png (320 × 180 Pixel, Anzeige bei 100 %) und
// Setup/Tipps/<name>@2x.png (640 × 360 Pixel, ab 125 %). Die Vorlage ist ein HTML-Ausschnitt; das Skript
// setzt ihn in den Rahmen aus tipps.css (dunkler Editor-Grund mit grauem Rand, in hellem und dunklem
// IDE-Thema lesbar) und fotografiert ihn mit Chromium über Playwright.
//
// Aufruf (aus dem Repository-Ordner):
//   node Tools/Tipps/Render-Tips.mjs              alle Vorlagen
//   node Tools/Tipps/Render-Tips.mjs referenzen   nur die genannten
// Playwright muss auffindbar sein (npm install playwright, oder global installiert mit NODE_PATH auf den
// globalen node_modules-Ordner); Chromium aus PLAYWRIGHT_BROWSERS_PATH bzw. „npx playwright install chromium“.
// Schriften: Segoe UI und Consolas, sonst DejaVu Sans und DejaVu Sans Mono; die Bilder im Repository sind mit
// DejaVu gerendert. Danach Tools/Check-Tips.ps1 laufen lassen.

import { createRequire } from 'node:module';
import { readFileSync, readdirSync, mkdirSync } from 'node:fs';
import { dirname, join, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const templates = join(here, 'Vorlagen');
const target = join(root, 'Setup', 'Tipps');
const css = readFileSync(join(here, 'tipps.css'), 'utf8');

// Größe der einfachen Datei in Pixeln = Anzeigegröße in logischen Pixeln (TAtlasTipCatalog.ImageWidth/Height).
const width = 320;
const height = 180;

const wanted = process.argv.slice(2);
const names = readdirSync(templates)
  .filter((file) => file.endsWith('.html'))
  .map((file) => basename(file, '.html'))
  .filter((name) => wanted.length === 0 || wanted.includes(name))
  .sort();
if (names.length === 0) {
  console.error('Keine Vorlage gefunden.');
  process.exit(1);
}
mkdirSync(target, { recursive: true });

function page(name) {
  const body = readFileSync(join(templates, name + '.html'), 'utf8');
  return `<!doctype html><html lang="de"><head><meta charset="utf-8"><style>${css}</style></head>` +
    `<body><div id="bild">${body}</div></body></html>`;
}

const browser = await chromium.launch();
try {
  for (const scale of [1, 2]) {
    const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: scale });
    const tab = await context.newPage();
    for (const name of names) {
      await tab.setContent(page(name), { waitUntil: 'load' });
      const file = join(target, scale === 1 ? `${name}.png` : `${name}@2x.png`);
      await tab.locator('#bild').screenshot({ path: file, omitBackground: false });
      console.log(file);
    }
    await context.close();
  }
} finally {
  await browser.close();
}
