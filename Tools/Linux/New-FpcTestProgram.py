#!/usr/bin/env python3
"""Erzeugt das Testprogramm für den FPC-Lauf (Test-Fpc.sh).

Aufruf: New-FpcTestProgram.py <Repo> <Programm.dpr> <Liste>

<Liste> nennt je Zeile eine Testunit (Leerzeilen und Zeilen mit # zählen nicht). Das Programm ruft jede
[Test]-Methode und jeden [TestCase] dieser Units auf, mit [Setup] und [TearDown] der Klasse; [Ignore]-Tests
entfallen. Es zählt bestandene und fehlgeschlagene Tests, schreibt fehlgeschlagene mit Meldung auf stdout
und endet mit Exit-Code 1, wenn einer fehlschlug. Den Rest (DUnitX-Attribute entfernen, Umwandlung für
FPC) erledigt Convert-ForFpc.py --tests.
"""
import os
import re
import sys

REPO, PROGRAM, LIST = sys.argv[1], sys.argv[2], sys.argv[3]
SKIP_DIRS = ('/.git', '/Output', '/Referenzprojekt')


def read_list(path):
    with open(path, encoding='utf-8-sig') as f:
        return [s.strip() for s in f if s.strip() and not s.strip().startswith('#')]


def index_units():
    found = {}
    for d, _, files in os.walk(REPO):
        rel = d[len(REPO):].replace('\\', '/') + '/'
        if any(s + '/' in rel for s in SKIP_DIRS):
            continue
        for f in files:
            if f.lower().endswith('.pas'):
                found.setdefault(f[:-4].lower(), os.path.join(d, f))
    return found


def literal(value, typ):
    value = value.strip()
    t = typ.lower()
    if t in ('string', 'unicodestring', 'char'):
        if len(value) >= 2 and value[0] == "'" and value[-1] == "'":
            return value
        return "'" + value.replace("'", "''") + "'"
    if t == 'boolean':
        return 'True' if value.lower() == 'true' else 'False'
    return value


def parameter_types(text):
    types = []
    if not text:
        return types
    for group in text.split(';'):
        g = re.sub(r'(?i)^\s*(const|var)\s+', '', group)
        names, typ = g.split(':')
        types.extend(typ.strip() for _ in names.split(','))
    return types


def calls_of(path):
    """(Klasse, Name, Aufruf, Setup, TearDown) je Test der Unit."""
    with open(path, encoding='utf-8-sig') as f:
        src = f.read().replace('\r\n', '\n')
    intf = src[:re.search(r'(?im)^implementation\b', src).start()]
    result = []
    fixtures = re.finditer(r'\[TestFixture[^\]]*\](?:\s*\[[^\]]*\])*\s*(\w+)\s*=\s*class\b(.*?)\bend;', intf, re.S)
    for fixture in fixtures:
        cls, body = fixture.group(1), fixture.group(2)
        setup = teardown = None
        tests = []
        attrs = []
        for line in body.split('\n'):
            s = line.strip()
            if s.startswith('['):
                attrs.append(s)
                continue
            m = re.match(r'(?i)procedure\s+(\w+)\s*(\((.*)\))?\s*;', s)
            if m:
                name, joined = m.group(1), ' '.join(attrs)
                if re.search(r'\[Setup\]', joined, re.I):
                    setup = name
                elif re.search(r'\[TearDown\]', joined, re.I):
                    teardown = name
                elif re.search(r'\[(Test|TestCase)\b', joined) and not re.search(r'\[Ignore\b', joined):
                    types = parameter_types(m.group(3))
                    cases = re.findall(r"\[TestCase\('([^']*)'\s*,\s*'((?:[^']|'')*)'(?:\s*,\s*'([^']*)')?\)\]", joined)
                    if types and cases:
                        for case, args, sep in cases:
                            values = args.replace("''", "'").split(sep or ',')
                            call = '%s(%s)' % (name, ', '.join(literal(v, types[i]) for i, v in enumerate(values)))
                            tests.append((name + '[' + case + ']', call))
                    elif not types:
                        tests.append((name, name))
                attrs = []
            elif s and not s.startswith('//'):
                attrs = []
        result.extend((cls, name, call, setup, teardown) for name, call in tests)
    return result


def main():
    units = read_list(LIST)
    index = index_units()
    missing = [u for u in units if u.lower() not in index]
    if missing:
        sys.stderr.write('Testunit nicht gefunden: %s\n' % ', '.join(missing))
        sys.exit(2)
    calls = []
    for u in units:
        calls.extend(calls_of(index[u.lower()]))
    name = os.path.splitext(os.path.basename(PROGRAM))[0]
    lines = ['program %s;' % name, '', 'uses', '  SysUtils, DUnitX.TestFramework,',
             '  ' + ',\n  '.join(units) + ';', '', 'var', '  Passed, Failed: Integer;', '']
    for number, (cls, test, call, setup, teardown) in enumerate(calls, 1):
        lines += ['procedure T%d;' % number, 'var', '  F: %s;' % cls, 'begin', '  F := %s.Create;' % cls, '  try',
                  '    try']
        if setup:
            lines.append('      F.%s;' % setup)
        lines += ['      try', '        F.%s;' % call, '      finally']
        if teardown:
            lines.append('        F.%s;' % teardown)
        lines += ['      end;', '      Inc(Passed);', '    except',
                  '      on E: ETestPass do Inc(Passed);',
                  "      on E: Exception do begin Inc(Failed); WriteLn('FAIL %s.%s: ', E.ClassName, ': ', E.Message); end;"
                  % (cls, test.replace("'", "''")),
                  '    end;', '  finally', '    F.Free;', '  end;', 'end;', '']
    lines += ['begin', '  DefaultSystemCodePage := 1252;']
    lines += ['  T%d;' % n for n in range(1, len(calls) + 1)]
    lines += ["  WriteLn('passed ', Passed, ' failed ', Failed);", '  if Failed > 0 then', '    Halt(1);', 'end.']
    with open(PROGRAM, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    sys.stderr.write('%d Testunits, %d Tests\n' % (len(units), len(calls)))


main()
