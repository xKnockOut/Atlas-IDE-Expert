# Atlas-Symbol

Das Symbol von Atlas: ein massives „A“ ohne sichtbaren Querstrich und eine Umlaufbahn. Die Bahn wächst aus dem rechten Fuß, läuft unten als schmaler werdender Schweif um das A herum und quert es oben mit einem Satelliten. Entwurf „G1a“ aus dem Thread „Atlas-Symbol“ vom 14.10.2026.

## Dateien

| Datei | Inhalt |
|---|---|
| `atlas-hell.ico` | Für helle Oberflächen: 16, 20, 24, 32, 40, 48, 64, 128 und 256 px (256 als PNG) |
| `atlas-dunkel.ico` | Dasselbe für dunkle Oberflächen |
| `atlas-hell-<px>.png`, `atlas-dunkel-<px>.png` | Einzelne Größen 16 bis 512 px, 32 Bit mit Alphakanal |
| `Quellen/atlas-symbol-*.svg` | Vektorquellen; `-klein` ist die Fassung für 16 bis 24 px (dickere Striche, ohne Satellit) |
| `Quellen/Erzeuge-Symbol.py` | Erzeugt die SVG-Quellen |
| `Quellen/Rendere-Symbol.py` | Rendert daraus PNG und ICO (Chromium und ImageMagick) |

Bis 24 px wird die kleine Fassung verwendet, ab 32 px die große.

## Farben

| | Hell | Dunkel |
|---|---|---|
| A | `#1C2340` | `#E8EBF4` |
| Bahn | `#D9692A` | `#F29A4A` |

Die Lücke zwischen Bahn und A ist ausgespart, also auf jedem Grund durchsichtig.

## Neu erzeugen

```
python3 Quellen/Erzeuge-Symbol.py Quellen
python3 Quellen/Rendere-Symbol.py Quellen .
```
