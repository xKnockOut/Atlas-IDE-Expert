#!/usr/bin/env python3
"""Bereitet den Quelltext von AtlasServer für Free Pascal (trunk, Linux) auf.

Aufruf: Convert-ForFpc.py <Repo> <Zielordner>

Kopiert das Programm Application/AtlasServer.dpr und die Hülle aller Units, die es
über uses erreicht, flach in den Zielordner und passt sie an FPC im Modus delphi an.
Die Anpassungen sind rein mechanisch und ändern keine Logik:

- Kopfzeile mit {$mode delphi} und den Modeswitches für Unicode-Strings,
  erweiterte Records, Typhelfer, Methodenreferenzen und anonyme Methoden.
- RTL-Units mit Delphi-Namensraum (System.SysUtils) auf die FPC-Namen (SysUtils).
  Units aus vcl-compat (System.JSON, System.IOUtils, System.RegularExpressions,
  System.Diagnostics, System.Threading, System.Hash, System.NetEncoding) behalten
  ihren Namen.
- Nicht-ASCII in Zeichenketten als #$XXXX, in Kommentaren als '?', damit die Codepage
  der Quelle keine Rolle spielt.
- In jede Unit kommt DelphiCompat (TProc, TFunc, TPredicate, TLightweightEvent).
- Delphi-Schreibweisen, die FPC anders liest: '>>' in Generics, TArray.Sort<T>(...),
  TStringBuilder (UnicodeString), verschachtelte generische Typen im Rumpf (Alias),
  Aufrufe generischer Methoden mitten im Ausdruck (Klammern).
- Ressourcen ({$R}) und {$MAXSTACKSIZE} entfallen; die Stapelgröße setzt der Linker
  (siehe Build-AtlasServer.sh).

Die Windows-Adapter (Atlas.Windows.*) erreicht der Linux-Bau nicht: Shell.Platform
wählt unter Linux die Adapter aus Packages/Atlas.Linux.
"""
import json
import os
import re
import sys

REPO, OUT = sys.argv[1], sys.argv[2]
ROOT = os.path.join(REPO, 'Application', 'AtlasServer.dpr')

# Ordner, deren Units der Server nie braucht (Tests, Installer, Referenzprojekt, Werkzeuge, Bauausgabe).
SKIP_DIRS = ('/.git', '/Tests', '/Setup', '/Tools/', '/Editors', '/docs', '/Output/')

MAP = {
    'system.sysutils': 'SysUtils', 'system.classes': 'Classes', 'system.math': 'Math',
    'system.strutils': 'StrUtils', 'system.types': 'Types', 'system.syncobjs': 'SyncObjs',
    'system.dateutils': 'DateUtils', 'system.character': 'Character', 'system.typinfo': 'TypInfo',
    'system.generics.collections': 'Generics.Collections', 'system.generics.defaults': 'Generics.Defaults',
    'system.rtti': 'Rtti', 'system.variants': 'Variants', 'system.zlib': 'ZStream',
    'system.masks': 'Masks', 'system.ioutils': 'AtlasIOUtils', 'system.widestrutils': 'SysUtils', 'system.ansistrings': 'SysUtils',
}
# Units ohne Gegenstück, deren Inhalt FPC in anderen Units mitbringt.
DROP = {'system.timespan', 'system.uitypes'}

QUALIFIED = re.compile(r"(?<![\w.])(" + '|'.join(re.escape(k) for k in sorted(MAP, key=len, reverse=True)) + r")\.(?=[A-Za-z_])", re.I)

HEAD = ('{$mode delphi}{$H+}{$codepage utf8}{$modeswitch unicodestrings}{$modeswitch advancedrecords}'
        '{$modeswitch typehelpers}{$modeswitch functionreferences}{$modeswitch anonymousfunctions}'
        '{$modeswitch prefixedattributes}{$warnings off}{$hints off}{$notes off}\n')


def index_units():
    found = {}
    for d, _, files in os.walk(REPO):
        rel = d[len(REPO):].replace('\\', '/') + '/'
        if any(s in rel for s in SKIP_DIRS) or 'Referenzprojekt' in rel:
            continue
        for f in files:
            if f.lower().endswith('.pas'):
                found.setdefault(f[:-4].lower(), os.path.join(d, f))
    return found


def mask(t):
    """Ersetzt Zeichenketten und Kommentare durch Leerzeichen (Zeilenumbrüche bleiben)."""
    r, i, n = list(t), 0, len(t)

    def blank(a, b):
        for k in range(a, min(b, n)):
            if r[k] != '\n':
                r[k] = ' '
    while i < n:
        c = t[i]
        if c == "'":
            j = t.find("'", i + 1)
            j = n - 1 if j < 0 else j
            blank(i, j + 1)
            i = j + 1
        elif t.startswith('//', i):
            j = t.find('\n', i)
            j = n if j < 0 else j
            blank(i, j)
            i = j
        elif c == '{':
            j = t.find('}', i)
            j = n - 1 if j < 0 else j
            blank(i, j + 1)
            i = j + 1
        elif t.startswith('(*', i):
            j = t.find('*)', i)
            j = n - 2 if j < 0 else j
            blank(i, j + 2)
            i = j + 2
        else:
            i += 1
    return ''.join(r)


class OriginalMatch:
    """Treffer im maskierten Text, dessen Gruppen den Originaltext liefern. Ein erneutes Suchen im Original fände
    Trennzeichen in Kommentaren (z. B. ';' in einem Kommentar innerhalb der uses-Klausel)."""

    def __init__(self, match, txt):
        self._match, self._txt = match, txt

    def group(self, index=0):
        start, end = self._match.span(index)
        return None if start < 0 else self._txt[start:end]

    def start(self, index=0):
        return self._match.start(index)

    def end(self, index=0):
        return self._match.end(index)


def sub_code(regex, fn, txt):
    """re.sub nur außerhalb von Zeichenketten und Kommentaren."""
    masked = mask(txt)
    parts, last = [], 0
    for m in regex.finditer(masked):
        parts.append(txt[last:m.start()])
        parts.append(fn(OriginalMatch(m, txt)))
        last = m.end()
    parts.append(txt[last:])
    return ''.join(parts)


USES = re.compile(r"\buses\b(.*?);", re.I | re.S)


DIRECTIVE = re.compile(r"\{\$(IFDEF|IFNDEF|IF|ELSE|ELSEIF|ENDIF|IFEND)\b([^}]*)\}", re.I)


def linux_branches(text):
    """Entfernt die Zweige {$IFDEF MSWINDOWS} (bzw. den ELSE-Zweig von {$IFNDEF MSWINDOWS}), damit die uses-Hülle
    nur die Units des Linux-Baus enthält. Andere Bedingungen bleiben stehen; FPC wertet sie selbst aus."""
    # stack: ist der Zweig aktiv; windows: stammt die Ebene von {$IFDEF/IFNDEF MSWINDOWS}.
    out, stack, windows_levels, last = [], [], [], 0
    for m in DIRECTIVE.finditer(text):
        kind, arg = m.group(1).upper(), m.group(2).strip().upper()
        active = all(stack)
        if active:
            out.append(text[last:m.start()])
        if kind in ('IFDEF', 'IFNDEF', 'IF'):
            windows = arg == 'MSWINDOWS' and kind != 'IF'
            if windows:
                stack.append(kind == 'IFNDEF')
            else:
                stack.append(True)
                if active:
                    out.append(m.group(0))
            windows_levels.append(windows)
        elif kind in ('ELSE', 'ELSEIF'):
            if windows_levels and windows_levels[-1]:
                stack[-1] = not stack[-1]
            elif all(stack):
                out.append(m.group(0))
        else:
            windows = windows_levels.pop() if windows_levels else False
            if stack:
                stack.pop()
            if not windows and all(stack):
                out.append(m.group(0))
        last = m.end()
    if all(stack):
        out.append(text[last:])
    return ''.join(out)



def uses_of(text):
    names = []
    for m in USES.finditer(mask(linux_branches(text))):
        body = re.sub(r"\{\$[^}]*\}", ' ', m.group(1))
        for part in body.split(','):
            p = part.strip().split()
            if p:
                names.append(p[0])
    return names


def fix_uses(m):
    body = m.group(1)
    # Kommentare entfernen (Direktiven bleiben): Ihre Wörter sind keine Unitnamen.
    body = re.sub(r"//[^\n]*|\{(?!\$)[^}]*\}|\(\*.*?\*\)", '', body, flags=re.S)
    # "Unit in 'Pfad'" im Programm: Die Units liegen flach im Zielordner.
    body = re.sub(r"\s+in\s+'[^']*'", '', body, flags=re.I)

    def rep(um):
        name = um.group(0)
        low = name.lower()
        if low in DROP:
            return '__DROP__'
        return MAP.get(low, name)
    body = re.sub(r"(?<!\{\$)(?<![\w$])[A-Za-z_][\w.]*", lambda um: um.group(0) if um.group(0).lower() == 'in' else rep(um), body)
    # Ein ausgelassener Eintrag behält seine Direktiven, sonst fehlte z. B. ein {$IFDEF} zum {$ENDIF}.
    items, pending = [], ''
    for item in body.split(','):
        if '__DROP__' in item:
            pending += ' ' + ' '.join(re.findall(r"\{\$[^}]*\}", item))
        else:
            items.append(pending + item)
            pending = ''
    if pending.strip():
        if items:
            items[-1] += pending
        else:
            return pending
    return 'uses' + ','.join(items) + ';'


def ascii_literal(lit):
    res = []
    for ch in lit:
        res.append(ch if ord(ch) < 128 else "'#$%04X'" % ord(ch))
    return ''.join(res)


def ascii_fix(t):
    """Nicht-ASCII nur in Zeichenketten als #$XXXX erhalten; in Kommentaren durch '?' ersetzen."""
    out, i, n = [], 0, len(t)
    while i < n:
        c = t[i]
        if c == "'":
            j = i + 1
            while j < n:
                if t[j] == "'":
                    if j + 1 < n and t[j + 1] == "'":
                        j += 2
                        continue
                    break
                j += 1
            lit = t[i:j + 1]
            if any(ord(x) > 127 for x in lit):
                lit = ascii_literal(lit)
            out.append(lit)
            i = j + 1
        elif t.startswith('//', i):
            j = t.find('\n', i)
            j = n if j < 0 else j
            out.append(''.join(x if ord(x) < 128 else '?' for x in t[i:j]))
            i = j
        elif c == '{':
            j = t.find('}', i)
            j = n if j < 0 else j
            out.append(''.join(x if ord(x) < 128 else '?' for x in t[i:j + 1]))
            i = j + 1
        elif t.startswith('(*', i):
            j = t.find('*)', i)
            j = n if j < 0 else j + 1
            out.append(''.join(x if ord(x) < 128 else '?' for x in t[i:j + 1]))
            i = j + 1
        else:
            out.append(c if ord(c) < 128 else '?')
            i += 1
    return ''.join(out)


GCALL = re.compile(r"\.(\w+)<[\w.]+(?:<[\w.]+(?:<[\w.]+\s*>)?\s*>)?\s*>(\(|)")
GTYPE = re.compile(r"(?<![\w.])\w+<[\w.]+(?:\s*,\s*[\w.]+)*(?:<[\w.]+\s*>)?\s*>\.\w+(\(|)")


def wrap_generic_calls(txt):
    """Klammert X.GetValue<T>(..) und TFoo<T>.Bar(..) ein; FPC liest sie sonst als Vergleich."""
    masked = mask(txt)
    ins = []
    for m in list(GCALL.finditer(masked)) + list(GTYPE.finditer(masked)):
        i = m.start()
        while i > 0:
            c = masked[i - 1]
            if c.isalnum() or c in '_.':
                i -= 1
            elif c in ')]':
                depth, j = 0, i - 1
                while j >= 0:
                    if masked[j] in ')]':
                        depth += 1
                    elif masked[j] in '([':
                        depth -= 1
                        if depth == 0:
                            break
                    j -= 1
                i = j
            else:
                break
        before = masked[max(0, i - 40):i].rstrip().lower()
        if re.search(r"\b(function|procedure|constructor|destructor|class|of|type|=)$", before):
            continue
        line_start = masked.rfind('\n', 0, i) + 1
        if re.match(r"\s*(function|procedure|constructor|destructor|class)\b", masked[line_start:i], re.I):
            continue
        e = m.end()
        if m.group(m.lastindex) == '(':
            depth, j = 1, e
            while j < len(masked) and depth:
                if masked[j] == '(':
                    depth += 1
                elif masked[j] == ')':
                    depth -= 1
                j += 1
            e = j
        ins.append((i, '('))
        ins.append((e, ')'))
    for pos, ch in sorted(ins, key=lambda p: (p[0], p[1] == '('), reverse=True):
        txt = txt[:pos] + ch + txt[pos:]
    return txt


NESTED = re.compile(r"\b([A-Za-z_]\w*)<((?:TArray|TList|TObjectList|TDictionary|TPair|TQueue|TStack|TObjectDictionary|TFunc|TProc|TPredicate)<[^<>;()]+>)\s*>")
KEEP_NESTED = ('TArray', 'TList', 'TObjectList', 'TDictionary', 'TObjectDictionary', 'TFunc', 'TProc', 'TPair',
               'TEnumerable', 'TQueue', 'TStack', 'IEnumerable', 'TPredicate', 'TComparer', 'IComparer')


def alias_nested(txt):
    """Verschachtelte Generics im Implementierungsteil (TFoo<TArray<X>>) über einen Typalias."""
    masked = mask(txt)
    im = re.search(r"(?i)\bimplementation\b", masked)
    if not im:
        return txt
    body = txt[im.end():]
    found = []

    def rep(m):
        if re.search(r"\bT\b", m.group(2)):
            return m.group(0)
        # Als Typ liest FPC TList<TArray<X>> richtig, im Ausdruck (TObjectList<TList<X>>.Create) nicht.
        in_expression = re.match(r"\s*\.", txt_body_after(m))
        if m.group(1) in KEEP_NESTED and not in_expression:
            return m.group(0)
        key = m.group(1) + '<' + m.group(2) + ' >'
        if key not in found:
            found.append(key)
        return '__GA%d' % (found.index(key) + 1)
    def txt_body_after(m):
        return body[m.end():m.end() + 20]
    body = sub_code(NESTED, rep, body)
    if not found:
        return txt
    decl = '\ntype\n' + ''.join('  __GA%d = %s;\n' % (i + 1, k) for i, k in enumerate(found))
    um = re.match(r"\s*uses\b[^;]*;", mask(body), re.I)
    pos = um.end() if um else 0
    return txt[:im.end()] + body[:pos] + decl + body[pos:]


def add_compat(txt, is_program):
    masked = mask(txt)
    if is_program:
        um = re.search(r"(?i)\buses\b", masked)
        pos = um.end()
        # cthreads muss vor allen anderen Units stehen; cwstring wandelt Zeichenketten (iconv), fpmonitor liefert TMonitor.
        return txt[:pos] + ' cthreads, cwstring, fpmonitor, DelphiCompat,' + txt[pos:]
    m = re.search(r"(?i)\binterface\b", masked)
    if not m:
        return txt
    um = re.match(r"\s*uses\b", masked[m.end():], re.I)
    if um:
        pos = m.end() + um.end()
        return txt[:pos] + ' DelphiCompat,' + txt[pos:]
    return txt[:m.end()] + '\nuses DelphiCompat;\n' + txt[m.end():]


def convert(txt, is_program):
    txt = txt.replace('\r\n', '\n')
    txt = ascii_fix(txt)
    txt = re.sub(r"(?im)^\s*\{\$R\s[^}]*\}\s*$", '', txt)
    txt = re.sub(r"(?im)\{\$MAXSTACKSIZE[^}]*\}", '', txt)
    txt = re.sub(r"(?im)\{\$APPTYPE[^}]*\}", '', txt)
    txt = sub_code(USES, fix_uses, txt)
    txt = add_compat(txt, is_program)
    # Qualifizierte Bezeichner (System.SysUtils.DeleteFile) wie die uses-Einträge umbenennen.
    txt = sub_code(QUALIFIED, lambda m: MAP[m.group(1).lower()] + '.', txt)
    while '>>' in mask(txt):
        txt = sub_code(re.compile(r">>"), lambda m: '> >', txt)
    txt = re.sub(r"\bTArray\.Sort<([^>]+)>\(", r"TArrayHelper<\1>.Sort(", txt)
    txt = re.sub(r"\bTArray\.BinarySearch<([^>]+)>\(", r"TArrayHelper<\1>.BinarySearch(", txt)
    txt = re.sub(r"\bTStringBuilder\b", 'TUnicodeStringBuilder', txt)
    txt = re.sub(r"\bTUTF8Encoding\.Create\(\s*False\s*\)", 'TUTF8NoBomEncoding.Create', txt, flags=re.I)
    txt = re.sub(r"\bSystem\.TMonitor\b", 'TMonitor', txt)
    if any(n.lower() == 'system.threading' for n in uses_of(txt)):
        # System.Threading von FPC deklariert eigene TProc<T>/TFunc<T> und verdeckt die aus DelphiCompat.
        txt = sub_code(re.compile(r"(?<![\w.])(TProc|TFunc|TPredicate)\b"), lambda m: 'DelphiCompat.' + m.group(1), txt)
    txt = alias_nested(txt)
    txt = wrap_generic_calls(txt)
    return HEAD + txt


WINDOWS_ONLY = re.compile(r"\b(?:Winapi|System\.Win|Vcl)\.", re.I)


def windows_only(text):
    """Unit, die Windows-APIs einbindet; im Linux-Bau steht an ihrer Stelle ein Adapter aus Atlas.Linux."""
    return any(WINDOWS_ONLY.match(n + '.') or WINDOWS_ONLY.match(n) for n in uses_of(text))


def drop_program_units(program, dropped):
    """Nimmt Windows-Units aus der uses-Liste des Programms (die Windows-Fassung braucht sie dort)."""
    def fix(m):
        items = [i for i in m.group(1).split(',') if i.strip().split() and i.strip().split()[0].lower() not in dropped]
        return 'uses' + ','.join(items) + ';'
    return sub_code(USES, fix, program)


def main():
    units = index_units()
    with open(ROOT, encoding='utf-8-sig') as f:
        program = f.read()
    seen, order, dropped = set(), [], set()
    queue = [n.lower() for n in uses_of(program)]
    while queue:
        u = queue.pop(0)
        if u in seen or u not in units:
            continue
        with open(units[u], encoding='utf-8-sig') as f:
            if windows_only(f.read()):
                dropped.add(u)
                seen.add(u)
                continue
        seen.add(u)
        order.append(u)
        with open(units[u], encoding='utf-8-sig') as f:
            text = f.read()
        queue.extend(n.lower() for n in uses_of(text) if n.lower() in units and n.lower() not in seen)
    os.makedirs(OUT, exist_ok=True)
    for u in order:
        with open(units[u], encoding='utf-8-sig') as f:
            text = f.read()
        with open(os.path.join(OUT, os.path.basename(units[u])), 'w', encoding='ascii', newline='\n') as f:
            f.write(convert(text, False))
    with open(os.path.join(OUT, 'AtlasServer.pas'), 'w', encoding='ascii', newline='\n') as f:
        f.write(convert(drop_program_units(program, dropped), True))
    with open(os.path.join(OUT, 'units.json'), 'w') as f:
        json.dump([os.path.relpath(units[u], REPO) for u in order], f, indent=1)
    print(len(order), 'Units,', len(dropped), 'Windows-Units ausgelassen:', ', '.join(sorted(dropped)))


main()
