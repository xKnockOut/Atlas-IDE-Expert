#!/usr/bin/env python3
"""Konstante Arrays mit zu vielen oder zu wenigen Elementen finden.

Delphi bricht bei `cNamen: array[TAufzaehlung] of string = ('a', 'b')` ab, wenn die Zahl der Elemente nicht zur
Aufzählung passt (E2072). Unter FPC fällt das nur auf, wenn die Unit dort übersetzt wird; Plugin-Units mit VCL
übersetzt die CI aber nur mit Delphi. Wer der Aufzählung einen Wert hinzufügt und eine der Namenslisten vergisst,
merkt es erst beim Delphi-Bau (Hilfe-Fensterliste, Namenslisten in Atlas.UI.Editor.Hide).

Das Skript liest alle .pas-Dateien unter Application, Packages und Tests, sammelt die Aufzählungstypen und prüft
jede Konstante der Form `<Name>: array[<Index>] of <Typ> = (…)`:
- Index ist eine Aufzählung (auch qualifiziert, auch Low(T)..High(T) oder ein Bereich ihrer Werte), Boolean oder
  ein Bereich aus Ganzzahlen;
- übersprungen werden mehrdimensionale Arrays, Aufzählungen mit festen Werten (`a = 1`), Namen, die es mit
  verschiedener Länge mehrfach gibt, und Stellen mit bedingter Übersetzung ({$IF…}).

Aufruf aus dem Wurzelordner:

    python3 Tools/Check-ConstArrays.py              # Exit-Code 1 bei einem Fehler
    python3 Tools/Check-ConstArrays.py --selbsttest
"""

import os
import re
import sys

ORDNER = ['Application', 'Packages', 'Tests']
# Absichtlich fehlerhafte Fälle für die Compilermeldungen (E2072 ist genau dieser Fehler).
AUSGENOMMEN = ['Tests/Compilermeldungen/Faelle/']
IDENT = r'[A-Za-z_]\w*'


def ohne_kommentare(text):
    """Ersetzt Kommentare und Zeichenketten durch Leerzeichen gleicher Länge (Zeilen bleiben erhalten).
    Compilerschalter {$…} bleiben als `{$`, damit bedingte Übersetzung erkennbar ist."""
    aus = []
    i = 0
    n = len(text)

    def leer(stueck):
        return ''.join('\n' if c == '\n' else ' ' for c in stueck)

    while i < n:
        c = text[i]
        if c == "'":
            j = i + 1
            while j < n:
                if text[j] == "'":
                    if j + 1 < n and text[j + 1] == "'":
                        j += 2
                        continue
                    break
                if text[j] == '\n':
                    break
                j += 1
            aus.append("'" + leer(text[i + 1:j]) + "'")
            i = j + 1
        elif text.startswith('//', i):
            j = text.find('\n', i)
            j = n if j < 0 else j
            aus.append(leer(text[i:j]))
            i = j
        elif c == '{':
            j = text.find('}', i)
            j = n - 1 if j < 0 else j
            stueck = text[i:j + 1]
            aus.append(('{$' + leer(stueck[2:])) if stueck.startswith('{$') else leer(stueck))
            i = j + 1
        elif text.startswith('(*', i):
            j = text.find('*)', i + 2)
            j = n - 2 if j < 0 else j
            aus.append(leer(text[i:j + 2]))
            i = j + 2
        else:
            aus.append(c)
            i += 1
    return ''.join(aus)


def klammer_inhalt(text, start):
    """Inhalt ab der öffnenden Klammer bei start bis zur passenden schließenden (ohne beide)."""
    tiefe = 0
    for i in range(start, len(text)):
        if text[i] in '([':
            tiefe += 1
        elif text[i] in ')]':
            tiefe -= 1
            if tiefe == 0:
                return text[start + 1:i]
    return None


def teile(inhalt):
    """Elemente auf oberster Ebene (Kommas außerhalb von Klammern)."""
    tiefe = 0
    zahl = 1
    for c in inhalt:
        if c in '([':
            tiefe += 1
        elif c in ')]':
            tiefe -= 1
        elif c == ',' and tiefe == 0:
            zahl += 1
    return zahl


ENUM = re.compile(r'\b(' + IDENT + r')\s*=\s*\(', re.S)
KONST = re.compile(r'\b(' + IDENT + r')\s*:\s*array\s*\[', re.I)


def aufzaehlungen(text):
    """{Name: [Werte]} der Aufzählungstypen im Text (ohne Kommentare)."""
    ergebnis = {}
    for treffer in ENUM.finditer(text):
        vorher = text[max(0, treffer.start() - 40):treffer.start()]
        if re.search(r'\b(const|var|function|procedure)\s*$', vorher, re.I):
            continue
        inhalt = klammer_inhalt(text, treffer.end() - 1)
        if not inhalt or '{$' in inhalt or '=' in inhalt or '(' in inhalt or ':' in inhalt:
            continue
        werte = [w.strip() for w in inhalt.split(',')]
        if all(re.fullmatch(IDENT, w) for w in werte):
            ergebnis.setdefault(treffer.group(1).lower(), []).append(werte)
    return ergebnis


def index_laenge(index, enums, werte_von):
    index = index.strip()
    if ',' in index:
        return None  # mehrdimensional
    name = index.split('.')[-1].lower()
    if '..' not in index and re.fullmatch(r'[\w.]+', index):
        if name == 'boolean':
            return 2
        return enums.get(name)
    bereich = re.fullmatch(r'(.+?)\.\.(.+)', index)
    if not bereich:
        return None
    links, rechts = bereich.group(1).strip(), bereich.group(2).strip()
    if re.fullmatch(r'-?\d+', links) and re.fullmatch(r'-?\d+', rechts):
        return int(rechts) - int(links) + 1
    low = re.fullmatch(r'Low\(\s*([\w.]+)\s*\)', links, re.I)
    high = re.fullmatch(r'High\(\s*([\w.]+)\s*\)', rechts, re.I)
    if low and high and low.group(1).lower() == high.group(1).lower():
        return enums.get(low.group(1).split('.')[-1].lower())
    a = werte_von.get(links.split('.')[-1].lower())
    b = werte_von.get(rechts.split('.')[-1].lower())
    if a and b and a[0] == b[0]:
        return b[1] - a[1] + 1
    return None


def pruefe_text(pfad, text, enums, werte_von):
    fehler = []
    for treffer in KONST.finditer(text):
        index = klammer_inhalt(text, treffer.end() - 1)
        if index is None:
            continue
        rest = text[treffer.end() + len(index) + 1:]
        typ = re.match(r'\s*of\s+(.*?)=\s*\(', rest, re.S | re.I)
        if not typ or re.search(r'\b(array|set)\b', typ.group(1), re.I) or ';' in typ.group(1):
            continue
        start = treffer.end() + len(index) + 1 + typ.end() - 1
        inhalt = klammer_inhalt(text, start)
        if inhalt is None or '{$' in inhalt:
            continue
        soll = index_laenge(index, enums, werte_von)
        if soll is None:
            continue
        ist = teile(inhalt)
        if ist != soll:
            zeile = text.count('\n', 0, treffer.start()) + 1
            fehler.append(f'{pfad}:{zeile}: {treffer.group(1)}: array[{index.strip()}] hat {ist} statt {soll} '
                          f'Elemente')
    return fehler


def lies(pfad):
    with open(pfad, 'rb') as datei:
        roh = datei.read()
    if roh.startswith(b'\xef\xbb\xbf'):
        roh = roh[3:]
    try:
        return roh.decode('utf-8')
    except UnicodeDecodeError:
        return roh.decode('latin-1')


def eindeutig(alle):
    """Nur Aufzählungen, deren Name überall dieselben Werte hat."""
    enums = {}
    werte_von = {}
    mehrdeutig = set()
    for name, varianten in alle.items():
        laengen = {len(v) for v in varianten}
        if len(laengen) == 1:
            enums[name] = laengen.pop()
            for pos, wert in enumerate(varianten[0]):
                schluessel = wert.lower()
                if schluessel in werte_von and werte_von[schluessel][0] != name:
                    mehrdeutig.add(schluessel)
                werte_von[schluessel] = (name, pos)
    for schluessel in mehrdeutig:
        werte_von.pop(schluessel, None)
    return enums, werte_von


def pruefe(texte):
    """texte: [(Pfad, Text)]. Liefert die Fehler."""
    bereinigt = [(pfad, ohne_kommentare(text)) for pfad, text in texte]
    alle = {}
    for _, text in bereinigt:
        for name, varianten in aufzaehlungen(text).items():
            alle.setdefault(name, []).extend(varianten)
    enums, werte_von = eindeutig(alle)
    fehler = []
    for pfad, text in bereinigt:
        fehler.extend(pruefe_text(pfad, text, enums, werte_von))
    return fehler


def selbsttest():
    quelle = '''unit T;
interface
type
  TFarbe = (Rot, Gruen, { Kommentar, mit Komma } Blau);
  TFeld = (fA = 1, fB);
const
  cGut: array[TFarbe] of string = ('rot', 'grün, mit Komma', 'blau');
  cKurz: array[TFarbe] of string = ('rot', 'grün');
  cLang: array[0..1] of Integer = (1, 2, 3);
  cBereich: array[Gruen..Blau] of Integer = (2, 3);
  cLowHigh: array[Low(TFarbe)..High(TFarbe)] of Integer = (1, 2);
  cRecords: array[Boolean] of TPoint = ((X: 1; Y: 2), (X: 3; Y: 4));
  cQualifiziert: array[T.TFarbe] of TFarbe = (TFarbe.Rot, TFarbe.Gruen, TFarbe.Blau);
  cFest: array[TFeld] of Integer = (1);
  cZwei: array[TFarbe, Boolean] of Integer = ((1, 2), (3, 4), (5, 6));
  cBedingt: array[TFarbe] of string = ('a', {$IFDEF X}'b',{$ENDIF} 'c');
'''
    erwartet = {'cKurz': (2, 3), 'cLang': (3, 2), 'cLowHigh': (2, 3)}
    fehler = pruefe([('T.pas', quelle)])
    gefunden = {}
    for zeile in fehler:
        treffer = re.search(r': (\w+): array\[.*\] hat (\d+) statt (\d+)', zeile)
        gefunden[treffer.group(1)] = (int(treffer.group(2)), int(treffer.group(3)))
    if gefunden != erwartet:
        print(f'Selbsttest fehlgeschlagen: erwartet {erwartet}, erhalten {gefunden}')
        return 1
    print('Selbsttest in Ordnung')
    return 0


def main():
    if '--selbsttest' in sys.argv[1:]:
        return selbsttest()
    wurzel = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    texte = []
    for ordner in ORDNER:
        for verzeichnis, _, dateien in os.walk(os.path.join(wurzel, ordner)):
            for datei in sorted(dateien):
                if datei.lower().endswith('.pas'):
                    pfad = os.path.join(verzeichnis, datei)
                    relativ = os.path.relpath(pfad, wurzel).replace(os.sep, '/')
                    if relativ.startswith(tuple(AUSGENOMMEN)):
                        continue
                    texte.append((os.path.relpath(pfad, wurzel).replace(os.sep, '/'), lies(pfad)))
    fehler = pruefe(texte)
    for zeile in fehler:
        print(zeile)
    print(f'Konstante Arrays: {len(fehler)} Fehler in {len(texte)} Dateien.')
    return 1 if fehler else 0


if __name__ == '__main__':
    sys.exit(main())
