#!/usr/bin/env python3
"""Vergleicht die dcc-Meldungen der Fälle aus Tests/Compilermeldungen mit den Treffern von Atlas.

Eingaben (Vorgabe: Output/Compilermeldungen, beide erzeugt von Tools/Build-Compilermeldungen.ps1):
  dcc.tsv                 alle Meldungen von dcc je Fall und Plattform (Wahrheit)
  atlas-strict*.json      AtlasServer --check ... --profile strict --format json
  atlas-standard*.json    dasselbe mit dem Profil standard (optional)

Welche Regel welchem Code entspricht, steht im Regelkatalog (compilerCodes und "like Xnnnn" in der
Beschreibung); nennt eine Meldung selbst Codes ("wie E2029"), gelten diese. ZUORDNUNG ergänzt Regeln,
deren Katalogeintrag keinen Code nennt.

Für jeden Fall und jeden Code, den dcc in der Datei des Falls meldet:
  erkannt         eine Regel von Atlas mit diesem Code meldet in derselben Datei
  anderer Code    Atlas meldet in derselben Zeile, aber mit einer Regel zu einem anderen Code
  verpasst        nichts davon
"Erwartet: -" im Kopf eines Falls heißt: Delphi 13 übersetzt ihn ohne Meldung.
Dazu Treffer von Atlas mit Compiler-Code, die dcc in dieser Datei nicht meldet (zusätzlich), und Fälle,
in denen dcc den erwarteten Code nicht meldet (Fall greift nicht).

Ausgabe: vergleich.json und vergleich.md im Ausgabeordner.

Aufruf: python3 Tools/Compare-Compilermeldungen.py [--input <Ordner>] [--output <Ordner>]
"""
import argparse
import csv
import glob
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CASE_DIR = os.path.join(ROOT, 'Tests', 'Compilermeldungen', 'Faelle')
CATALOG = os.path.join(ROOT, 'Packages', 'Atlas.Common', 'Katalog', 'regelkatalog.json')
CODE = re.compile(r'(?<![\w.])([EWHFX]\d{4})\b')
CASE_NAME = re.compile(r'^(Cm\.?([EWHF]\d{4})\w*)\.(pas|dpr|dpk)$')
# Folgemeldungen, die nur sagen, dass eine benutzte Unit nicht übersetzt wurde.
FOLGEMELDUNGEN = {'F2063', 'F2220'}
# Regeln, deren Katalogeintrag keinen Code nennt.
ZUORDNUNG = {
    'result-not-set': ['W1035'],
    'possibly-uninitialized': ['W1036'],
}


def rule_codes():
    with open(CATALOG, encoding='utf-8-sig') as f:
        rules = json.load(f)['rules']
    result = {}
    for rule in rules:
        codes = set(rule.get('compilerCodes') or []) | set(CODE.findall(rule.get('description', '')))
        codes |= set(ZUORDNUNG.get(rule['id'], []))
        if codes:
            result[rule['id']] = codes
    return result


def read_cases():
    cases = {}
    for name in sorted(os.listdir(CASE_DIR)):
        m = CASE_NAME.match(name)
        if not m:
            continue
        path = os.path.join(CASE_DIR, name)
        expected, title, platform = m.group(2), '', ''
        raw = open(path, 'rb').read()
        if raw.startswith(b'\xff\xfe\x00\x00'):
            text = raw[4:].decode('utf-32-le')
        else:
            text = raw.decode('utf-8-sig', errors='replace')
        lines = text.splitlines()
        for line in lines[:15]:
            if line.startswith('// %s ' % m.group(2)) and not title:
                title = line[len('// %s ' % m.group(2)):].strip()
            mm = re.match(r'//\s*Erwartet:\s*(.+)', line)
            if mm:
                expected = mm.group(1).strip()
            mm = re.match(r'//\s*Plattform:\s*(.+)', line)
            if mm:
                platform = mm.group(1).strip()
        marks = {}
        for number, line in enumerate(lines, 1):
            mm = re.search(r'// <- ([A-Z]\d{4}(?: [A-Z]\d{4})*)', line)
            if mm:
                marks[number] = mm.group(1).split()
        cases[m.group(1)] = {'case': m.group(1), 'file': name, 'code': m.group(2), 'expected': expected.split()[0],
                             'title': title, 'platform': platform, 'marks': marks}
    return cases


def read_dcc(path):
    rows = defaultdict(list)
    with open(path, encoding='utf-8-sig', newline='') as f:
        for row in csv.DictReader(f, delimiter='\t'):
            rows[row['Fall']].append(row)
    return rows


def read_atlas(pattern):
    findings = defaultdict(list)
    files = sorted(glob.glob(pattern))
    for path in files:
        with open(path, encoding='utf-8-sig') as f:
            data = json.load(f)
        for entry in data.get('files', []):
            name = os.path.basename(entry['path'].replace('\\', '/'))
            for finding in entry.get('findings', []):
                findings[name].append({'rule': finding['rule'], 'line': finding['range']['start']['line'] + 1,
                                       'severity': finding.get('severity', ''), 'message': finding.get('message', '')})
    return findings, files


def finding_codes(finding, codes_by_rule):
    own = set(CODE.findall(finding['message']))
    if own:
        return own
    return codes_by_rule.get(finding['rule'], set())


def compare(cases, dcc, strict, standard, codes_by_rule):
    results = []
    for key, case in cases.items():
        rows = dcc.get(key, [])
        built = bool(rows)
        dcc_codes = defaultdict(set)      # Code -> Zeilen in der Datei des Falls
        dcc_other = defaultdict(set)      # Code -> Dateien (Hilfsunits)
        texts = {}
        platforms = sorted(set(r['Plattform'] for r in rows))
        for r in rows:
            code = r['Code']
            if not code or code in FOLGEMELDUNGEN:
                continue
            texts.setdefault(code, r['Text'])
            if r['Datei'] == case['file'] or not r['Datei']:
                dcc_codes[code].add(int(r['Zeile']) if r['Zeile'] else 0)
            else:
                dcc_other[code].add(r['Datei'])
        atlas = []
        for finding in strict.get(case['file'], []):
            codes = finding_codes(finding, codes_by_rule)
            if not codes:
                continue
            in_standard = any(f['rule'] == finding['rule'] and f['line'] == finding['line']
                              for f in standard.get(case['file'], []))
            atlas.append(dict(finding, codes=sorted(codes), standard=in_standard))
        checks = []
        for code, lines in sorted(dcc_codes.items()):
            hits = [f for f in atlas if code in f['codes']]
            if hits:
                status = 'erkannt'
                same_line = any(f['line'] in lines for f in hits)
                standard_hit = any(f['standard'] for f in hits)
                rules = sorted(set(f['rule'] for f in hits))
            else:
                near = [f for f in atlas if f['line'] in lines]
                status = 'anderer Code' if near else 'verpasst'
                same_line = bool(near)
                standard_hit = any(f['standard'] for f in near)
                rules = sorted(set('%s (%s)' % (f['rule'], ', '.join(f['codes'])) for f in near))
            checks.append({'code': code, 'lines': sorted(lines), 'text': texts.get(code, ''), 'status': status,
                           'sameLine': same_line, 'standard': standard_hit, 'rules': rules})
        extra = [f for f in atlas if not (set(f['codes']) & set(dcc_codes))]
        if case['expected'] == '-':
            # Fall, den Delphi 13 übersetzt: Jeder Atlas-Treffer mit Compiler-Code ist zusätzlich.
            expected_hit = not dcc_codes and not dcc_other
        else:
            expected_hit = case['expected'] in dcc_codes or case['expected'] in dcc_other
        results.append({
            'case': key, 'file': case['file'], 'code': case['code'], 'expected': case['expected'],
            'title': case['title'], 'platform': case['platform'], 'built': built, 'platforms': platforms,
            'dccCodes': sorted(dcc_codes), 'dccOther': {c: sorted(v) for c, v in dcc_other.items()},
            'expectedHit': expected_hit, 'checks': checks,
            'extra': [{'rule': f['rule'], 'line': f['line'], 'codes': f['codes'], 'message': f['message'],
                       'standard': f['standard']} for f in extra],
        })
    return results


def summary(results):
    s = defaultdict(int)
    for r in results:
        s['faelle'] += 1
        if not r['built']:
            s['nichtGebaut'] += 1
            continue
        if not r['expectedHit']:
            s['greiftNicht'] += 1
        for c in r['checks']:
            s['dccCodes'] += 1
            s[c['status']] += 1
            if c['status'] == 'erkannt' and c['standard']:
                s['erkanntStandard'] += 1
        if r['extra']:
            s['mitZusaetzlichen'] += 1
            s['zusaetzlich'] += len(r['extra'])
    return dict(s)


def markdown(results, s):
    out = ['# Atlas gegen dcc: Compilermeldungen', '',
           '| Kennzahl | Anzahl |', '|---|---|']
    for key, label in [('faelle', 'Fälle'), ('nichtGebaut', 'nicht gebaut'), ('greiftNicht', 'Fall greift nicht (dcc meldet den erwarteten Code nicht)'),
                       ('dccCodes', 'Codes, die dcc meldet'), ('erkannt', 'davon von Atlas erkannt (strict)'),
                       ('erkanntStandard', 'davon auch im Profil standard'), ('anderer Code', 'Atlas meldet einen anderen Code'),
                       ('verpasst', 'verpasst'), ('zusaetzlich', 'zusätzliche Atlas-Treffer mit Compiler-Code')]:
        out.append('| %s | %d |' % (label, s.get(key, 0)))
    out += ['', '| Fall | erwartet | dcc meldet | Atlas | Regeln | zusätzlich |', '|---|---|---|---|---|---|']
    for r in results:
        if not r['built']:
            out.append('| %s | %s | nicht gebaut | | | |' % (r['case'], r['expected']))
            continue
        dcc_text = ', '.join(r['dccCodes']) or '–'
        status = '; '.join('%s %s' % (c['code'], c['status']) for c in r['checks']) or '–'
        rules = '; '.join(', '.join(c['rules']) for c in r['checks'] if c['rules'])
        extra = '; '.join('%s (%s)' % (e['rule'], ', '.join(e['codes'])) for e in r['extra'])
        out.append('| %s | %s | %s | %s | %s | %s |' % (r['case'], r['expected'], dcc_text, status, rules, extra))
    return '\n'.join(out) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', default=os.path.join(ROOT, 'Output', 'Compilermeldungen'))
    parser.add_argument('--output', default=None)
    args = parser.parse_args()
    output = args.output or args.input
    dcc_file = os.path.join(args.input, 'dcc.tsv')
    if not os.path.exists(dcc_file):
        print('Nicht gefunden: %s' % dcc_file, file=sys.stderr)
        return 3
    cases = read_cases()
    dcc = read_dcc(dcc_file)
    strict, strict_files = read_atlas(os.path.join(args.input, 'atlas-strict*.json'))
    standard, _ = read_atlas(os.path.join(args.input, 'atlas-standard*.json'))
    if not strict_files:
        print('Keine Atlas-Ergebnisse (atlas-strict*.json) in %s' % args.input, file=sys.stderr)
        return 3
    results = compare(cases, dcc, strict, standard, rule_codes())
    s = summary(results)
    os.makedirs(output, exist_ok=True)
    with open(os.path.join(output, 'vergleich.json'), 'w', encoding='utf-8') as f:
        json.dump({'summary': s, 'cases': results}, f, ensure_ascii=False, indent=1)
    with open(os.path.join(output, 'vergleich.md'), 'w', encoding='utf-8') as f:
        f.write(markdown(results, s))
    print(json.dumps(s, ensure_ascii=False), file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
