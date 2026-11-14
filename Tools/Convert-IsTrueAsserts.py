#!/usr/bin/env python3
# Stellt Assert.IsTrue(A = B), Assert.IsFalse(A <> B), Assert.IsTrue(X = nil), Assert.IsTrue(Assigned(X)) und
# dasselbe mit not in DUnitX-Testunits auf AreEqual, AreNotEqual, AreSame, IsNull bzw. IsNotNull um (#2197, Regel
# dunitx-istrue-equality). Beim Fehlschlag meldet DUnitX dann beide Werte statt nur „Bedingung gilt nicht“.
#
# Aufruf:
#   python3 Tools/Convert-IsTrueAsserts.py list  <Datei oder Ordner> …   Fundstellen mit vermuteter Art auflisten
#   python3 Tools/Convert-IsTrueAsserts.py apply <Datei oder Ordner> … [--kinds <Datei>] [--with-guesses]
#
# Die Art jeder Fundstelle bestimmt die erzeugte Form. Sie wird aus Literalen und den Deklarationen der Testunit
# vermutet; was sich nicht sicher bestimmen lässt, bleibt unverändert und steht mit „?“ in der Liste. In einer
# Artendatei (--kinds) steht je Zeile „<Pfad>:<Zeile>[:<Spalte>] <Art>“ (Pfad wie in der Liste); sie gewinnt vor der
# Vermutung. Arten:
#   string            Assert.AreEqual(E, A)                       Overload für string
#   int               Assert.AreEqual(E, A)                       beide Seiten Integer (Length/High/Low/Count in
#                                                                 Integer(...) gefasst)
#   bool              Assert.IsTrue(X)/IsFalse(X) bei True/False-Literal, sonst Assert.AreEqual<Boolean>(E, A)
#   float[:Toleranz]  Assert.AreEqual(Double(E), Double(A), Toleranz)   Standardtoleranz 1E-9
#   T:<Typ>           Assert.AreEqual<Typ>(E, A)                  Aufzählungen, Mengen, Int64, Cardinal, Char,
#                                                                 NativeInt, Zeiger, TDateTime genau, Klassenreferenzen
#   same              Assert.AreSame(E, A) bzw. Assert.AreNotSame(E, A) (Objekte oder Interfaces, nicht gemischt)
#   null              IsNull/IsNotNull (Klasse, Interface, Zeiger)
#   keep              nicht umstellen (Liste nennt es weiter; Grund im Pull Request bzw. an die Regel melden)
#
# Ausdrücklicher Typ statt Überladungsauswahl: Delphi 12, Delphi 13 und FPC wählen bei Ordinaltypen verschieden
# (Integer/Int64/Cardinal, NativeInt aus Length); AreEqual<T> mit Typ ist überall eindeutig.
# Records: AreEqual<T> vergleicht binär (verwaltete Felder wie string als Zeiger) und passt daher nicht; feldweise
# vergleichen oder keep. Gleitkomma: nie genau vergleichen, Toleranz passend zur Größe wählen.
#
# Schreibt UTF-8 mit BOM und behält die Zeilenenden der Datei. Lange Zeilen (über 120 Zeichen) werden nach dem
# erwarteten Wert umbrochen.

import argparse
import os
import re
import sys

MAX_LINE = 120
DEFAULT_TOLERANCE = '1E-9'

RE_CALL = re.compile(r'\b((?:DUnitX\.TestFramework\.)?Assert)\s*\.\s*(IsTrue|IsFalse)\s*\(', re.I)
RE_DECL = re.compile(r'\b([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*:\s*((?:array\s+of\s+)?[A-Za-z_][\w.]*(?:<[^;:=()]*?>)?)'
                     r'(?=\s*(?:[;)=\]]|read\b|write\b|index\b|default\b|deprecated\b|absolute\b))', re.I)
RE_FUNC = re.compile(r'\bfunction\s+(?:[A-Za-z_]\w*\.)*([A-Za-z_]\w*)\s*(?:\([^)]*\))?\s*:\s*([A-Za-z_][\w.]*(?:<[^;]*?>)?)', re.I)
RE_INT_LIT = re.compile(r'^-?\s*(\$[0-9A-Fa-f]+|[0-9]+)$')
RE_FLOAT_LIT = re.compile(r'^-?\s*[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$')
RE_IDENT = re.compile(r'^[A-Za-z_]\w*$')
RE_GENERIC_ARGS = re.compile(r'<[\w.]+(?:\s*,\s*[\w.]+)*>(?=\s*[.(\[])')
RE_QUALIFIED = re.compile(r'^[A-Za-z_]\w*(\.[A-Za-z_]\w*)+$')

STRING_TYPES = {'string', 'unicodestring', 'tcaption', 'tfilename', 'widestring', 'ansistring', 'utf8string',
                'rawbytestring', 'shortstring'}
INT_TYPES = {'integer', 'longint', 'smallint', 'shortint', 'word', 'byte'}
GENERIC_ORDINAL = {'int64': 'Int64', 'uint64': 'UInt64', 'cardinal': 'Cardinal', 'longword': 'Cardinal',
                   'nativeint': 'NativeInt', 'nativeuint': 'NativeUInt', 'char': 'Char', 'widechar': 'Char',
                   'ansichar': 'AnsiChar', 'tdatetime': 'TDateTime', 'tdate': 'TDate', 'ttime': 'TTime',
                   'pointer': 'Pointer', 'thandle': 'THandle', 'hwnd': 'HWND', 'tcolor': 'TColor',
                   'tguid': 'TGUID', 'uint32': 'UInt32', 'int32': 'Int32', 'uint16': 'UInt16', 'int16': 'Int16',
                   'uint8': 'UInt8', 'int8': 'Int8', 'tclass': 'TClass'}
FLOAT_TYPES = {'double', 'single', 'extended', 'real', 'currency'}
BOOL_TYPES = {'boolean', 'bytebool', 'wordbool', 'longbool'}
# Eigenschaften und Funktionen mit bekanntem Ergebnistyp.
KNOWN_MEMBERS = {
    'count': 'int', 'text': 'string', 'name': 'string', 'caption': 'string', 'hint': 'string',
    'tostring': 'string', 'classname': 'string', 'unitname': 'string', 'tojson': 'string', 'value': None,
    'width': 'int', 'height': 'int', 'left': 'int', 'top': 'int', 'right': 'int', 'bottom': 'int',
    'line': 'int', 'character': 'int', 'column': 'int', 'tag': 'int', 'itemindex': 'int',
    'checked': 'bool', 'visible': 'bool', 'enabled': 'bool', 'found': 'bool', 'success': 'bool',
}
KNOWN_FUNCS = {
    'length': 'int', 'high': 'int', 'low': 'int', 'pos': 'int', 'ord': 'int', 'trunc': 'T:Int64',
    'round': 'T:Int64', 'copy': 'string', 'trim': 'string', 'lowercase': 'string', 'uppercase': 'string',
    'inttostr': 'string', 'format': 'string', 'quotedstr': 'string', 'extractfilename': 'string',
    'extractfilepath': 'string', 'extractfileext': 'string', 'stringreplace': 'string', 'sametext': 'bool',
    'samestr': 'bool', 'fileexists': 'bool', 'directoryexists': 'bool', 'chr': 'T:Char', 'sizeof': 'int',
    'getenvironmentvariable': 'string', 'includetrailingpathdelimiter': 'string', 'changefileext': 'string',
    'floattostr': 'string', 'booltostr': 'string', 'guidtostring': 'string', 'string.join': 'string',
}
COUNT_LIKE = re.compile(r'^(Length|High|Low)\s*\(', re.I)


# ---------------------------------------------------------------------------------------------- Lexikalisches

def skip_string(text, i):
    """i zeigt auf ' ; liefert Index hinter dem Literal (auch '' im Literal)."""
    i += 1
    while i < len(text):
        if text[i] == "'":
            if i + 1 < len(text) and text[i + 1] == "'":
                i += 2
                continue
            return i + 1
        i += 1
    return i


def skip_comment(text, i):
    """Liefert Index hinter einem Kommentar ab i oder i, wenn keiner beginnt."""
    if text.startswith('//', i):
        j = text.find('\n', i)
        return len(text) if j < 0 else j
    if text.startswith('(*', i):
        j = text.find('*)', i + 2)
        return len(text) if j < 0 else j + 2
    if text[i:i + 1] == '{':
        j = text.find('}', i + 1)
        return len(text) if j < 0 else j + 1
    return i


def code_mask(text):
    """Bool-Liste: True, wo Code steht (nicht Kommentar, nicht String)."""
    mask = [True] * len(text)
    i = 0
    while i < len(text):
        c = text[i]
        if c == "'":
            j = skip_string(text, i)
            for k in range(i, j):
                mask[k] = False
            i = j
            continue
        j = skip_comment(text, i)
        if j != i:
            for k in range(i, j):
                mask[k] = False
            i = j
            continue
        i += 1
    return mask


def split_top(text, seps):
    """Teilt an Trennern auf oberster Ebene (Klammern, eckige Klammern, Strings, Kommentare beachtet).
    seps: Liste von Trennern; liefert [(Teil, Trenner)]."""
    parts = []
    depth = 0
    start = 0
    i = 0
    while i < len(text):
        c = text[i]
        if c == "'":
            i = skip_string(text, i)
            continue
        j = skip_comment(text, i)
        if j != i:
            i = j
            continue
        if c in '([':
            depth += 1
        elif c in ')]':
            depth -= 1
        elif depth == 0:
            for sep in seps:
                if text.startswith(sep, i):
                    parts.append((text[start:i], sep))
                    i += len(sep)
                    start = i
                    break
            else:
                i += 1
                continue
            continue
        i += 1
    parts.append((text[start:], None))
    return parts


def find_close(text, open_index):
    """open_index zeigt auf '('; liefert Index der passenden ')'."""
    depth = 0
    i = open_index
    while i < len(text):
        c = text[i]
        if c == "'":
            i = skip_string(text, i)
            continue
        j = skip_comment(text, i)
        if j != i:
            i = j
            continue
        if c in '([':
            depth += 1
        elif c in ')]':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def strip_parens(expr):
    e = expr.strip()
    while e.startswith('(') and find_close(e, 0) == len(e) - 1:
        e = e[1:-1].strip()
    return e


def has_top_word(expr, words):
    """Steht eines der Schlüsselwörter (and, or …) auf oberster Ebene?"""
    depth = 0
    i = 0
    while i < len(expr):
        c = expr[i]
        if c == "'":
            i = skip_string(expr, i)
            continue
        if c in '([':
            depth += 1
        elif c in ')]':
            depth -= 1
        elif depth == 0 and (c.isalpha() or c == '_') and (i == 0 or not (expr[i - 1].isalnum() or expr[i - 1] in '_.')):
            m = re.match(r'[A-Za-z_]\w*', expr[i:])
            if m.group(0).lower() in words:
                return True
            i += len(m.group(0))
            continue
        i += 1
    return False


def split_compare(expr):
    """Teilt A = B bzw. A <> B auf oberster Ebene; None, wenn kein einfacher Vergleich."""
    depth = 0
    i = 0
    hits = []
    while i < len(expr):
        c = expr[i]
        if c == "'":
            i = skip_string(expr, i)
            continue
        if c in '([':
            depth += 1
        elif c in ')]':
            depth -= 1
        elif depth == 0:
            if expr.startswith('<>', i):
                hits.append((i, '<>'))
                i += 2
                continue
            generic = RE_GENERIC_ARGS.match(expr, i)
            if c == '<' and i > 0 and (expr[i - 1].isalnum() or expr[i - 1] == '_') and generic:
                # Typargumente eines Aufrufs (Part<TFoo>.Button), kein Vergleich.
                i = generic.end()
                continue
            if expr.startswith('<=', i) or expr.startswith('>=', i) or expr.startswith(':=', i):
                return None
            if c == '=':
                hits.append((i, '='))
            elif c in '<>':
                return None
        i += 1
    if len(hits) != 1:
        return None
    pos, op = hits[0]
    left = expr[:pos].strip()
    right = expr[pos + len(op):].strip()
    if not left or not right:
        return None
    if has_top_word(left, {'and', 'or', 'xor', 'in', 'is', 'as'}) or has_top_word(right, {'and', 'or', 'xor', 'in', 'is', 'as'}):
        return None
    return left, op, right


# ---------------------------------------------------------------------------------------------- Typen raten

class Declarations:
    """Deklarationen der Unit: Name → Typ (zuletzt deklariert gewinnt nicht; lokal vor global über Position)."""

    def __init__(self, text, glob=None):
        self.glob = glob
        self.entries = []  # (Position, Name klein, Typ)
        mask = code_mask(text)
        # Kommentare und Strings durch Leerzeichen ersetzen (Positionen bleiben), damit Aufzählungen mit
        # Kommentaren zwischen den Werten erkannt werden.
        text = ''.join(c if mask[i] or c in '\r\n' else ' ' for i, c in enumerate(text))
        mask = [True] * len(text)
        for m in RE_DECL.finditer(text):
            if not mask[m.start()]:
                continue
            typ = m.group(2).strip()
            if typ.lower() in ('class', 'record', 'interface', 'procedure', 'function', 'reference', 'set', 'array'):
                continue
            for name in m.group(1).split(','):
                self.entries.append((m.start(), name.strip().lower(), typ))
        for m in RE_FUNC.finditer(text):
            if mask[m.start()]:
                self.entries.append((m.start(), m.group(1).lower(), m.group(2).strip()))
        self.enum_types = {}
        self.record_types = set()
        self.set_types = set()
        self.class_types = set()
        self.enum_values = {}
        for m in re.finditer(r'\b([A-Za-z_]\w*)\s*=\s*\(\s*([A-Za-z_]\w*(?:\s*=\s*[^,)]+)?(?:\s*,\s*[A-Za-z_]\w*(?:\s*=\s*[^,)]+)?)*)\s*\)\s*;', text):
            if mask[m.start()]:
                self.enum_types[m.group(1).lower()] = m.group(1)
                for value in m.group(2).split(','):
                    name = value.split('=')[0].strip().lower()
                    self.enum_values.setdefault(name, set()).add(m.group(1))
        for m in re.finditer(r'\b([A-Za-z_]\w*)\s*=\s*(?:packed\s+)?record\b', text, re.I):
            self.record_types.add(m.group(1).lower())
        for m in re.finditer(r'\b([A-Za-z_]\w*)\s*=\s*set\s+of\b', text, re.I):
            self.set_types.add(m.group(1).lower())
        for m in re.finditer(r'\b([A-Za-z_]\w*)\s*=\s*class\b(?!\s+of)', text, re.I):
            self.class_types.add(m.group(1).lower())
        # Mitglieder je Typ: Einträge zwischen „TName = record/class/interface“ und dem nächsten solchen Kopf.
        self.type_members = {}
        heads = [(m.start(), m.group(1).lower()) for m in re.finditer(
            r'\b([A-Za-z_]\w*)\s*=\s*(?:packed\s+)?(?:record\b|class\b(?!\s+of)(?!\s*;)|interface\b(?!\s*;))',
            text, re.I)]
        heads.append((len(text), None))
        for (start, name), (end, _) in zip(heads, heads[1:]):
            impl = text.find('implementation', start, end)
            if impl >= 0:
                end = impl
            members = self.type_members.setdefault(name, {})
            for p, n, t in self.entries:
                if start < p < end and n not in members:
                    members[n] = t
        self.proc_types = set()
        for m in re.finditer(r'\b([A-Za-z_]\w*)\s*=\s*(?:reference\s+to\b|procedure\b|function\b)', text, re.I):
            self.proc_types.add(m.group(1).lower())
        self.proc_types |= {'tproc', 'tfunc', 'tpredicate', 'tnotifyevent', 'tthreadmethod', 'tthreadprocedure'}
        if glob is not None:
            self.enum_types.update(glob.enum_types)
            for k, v in glob.enum_values.items():
                self.enum_values.setdefault(k, set()).update(v)
            self.record_types |= glob.record_types
            self.set_types |= glob.set_types
            self.class_types |= glob.class_types
            self.proc_types |= glob.proc_types

    def members_of(self, typ):
        """Mitglieder eines Typs (Name klein → Typ), zuerst aus der Unit, dann aus dem Repository."""
        local = self.type_members.get(typ.lower())
        if local:
            return local
        if self.glob is not None:
            return self.glob.type_members.get(typ.lower())
        return None

    def is_type(self, name):
        n = name.lower()
        return (n in self.type_members or n in self.enum_types or
                (self.glob is not None and n in self.glob.type_members))

    def type_of(self, name, pos):
        name = name.lower()
        best = None
        for p, n, t in self.entries:
            if n == name and p < pos:
                best = t
        if best is None:
            for p, n, t in self.entries:
                if n == name:
                    best = t
                    break
        if best is None and self.glob is not None:
            types = self.glob.members.get(name)
            if types and len(types) == 1:
                best = next(iter(types))
        return best


class GlobalIndex:
    """Typen und Mitglieder aller Units des Repositorys (alle Ordner außer Output): Aufzählungen, Records, Mengen,
    Klassen und je Name die deklarierten Typen. Ein Name mit genau einem Typ im ganzen Repository gilt als dieser."""

    def __init__(self, root):
        self.enum_types = {}
        self.enum_values = {}
        self.record_types = set()
        self.set_types = set()
        self.class_types = set()
        self.proc_types = set()
        self.type_members = {}
        self.members = {}
        for value in ('wrSignaled', 'wrTimeout', 'wrAbandoned', 'wrError', 'wrIOCompletion'):
            self.enum_values.setdefault(value.lower(), set()).add('TWaitResult')
        self.enum_types['twaitresult'] = 'TWaitResult'
        subs = [n for n in sorted(os.listdir(root)) if os.path.isdir(os.path.join(root, n)) and n not in ('Output', '.git')]
        for sub in subs:
            for path in files_of([os.path.join(root, sub)]):
                try:
                    text, _ = read(path)
                except (UnicodeDecodeError, OSError):
                    continue
                d = Declarations(text)
                for k, v in d.enum_types.items():
                    self.enum_types[k] = v
                for k, v in d.enum_values.items():
                    self.enum_values.setdefault(k, set()).update(v)
                self.record_types |= d.record_types
                self.set_types |= d.set_types
                self.class_types |= d.class_types
                self.proc_types |= d.proc_types
                for k, v in d.type_members.items():
                    target = self.type_members.setdefault(k, {})
                    for n, t in v.items():
                        target.setdefault(n, t)
                for _, n, t in d.entries:
                    self.members.setdefault(n, set()).add(t.split('.')[-1] if '<' not in t else t)


RE_SEGMENT = re.compile(r'\s*([A-Za-z_]\w*)\s*((?:\((?:[^()]|\([^()]*\))*\)|\[[^\]]*\])*)\s*(?:\.|$)')


def element_type(typ):
    m = re.match(r'^(?:TArray<(.+)>|array\s+of\s+(.+))$', typ, re.I)
    if m:
        return (m.group(1) or m.group(2)).strip()
    m = re.match(r'^T(?:Object)?List<(.+)>$', typ, re.I)
    if m:
        return m.group(1).strip()
    return None


def type_of_path(expr, pos, decls):
    """Typ eines Ausdrucks a.b[i].c(…): erster Name aus den Deklarationen (oder ein Typname), dann Mitglied für
    Mitglied über die Typen. None, wenn eine Stufe unbekannt ist."""
    e = strip_parens(expr)
    segments = []
    i = 0
    while i < len(e):
        m = RE_SEGMENT.match(e, i)
        if not m or m.end() == i:
            return None
        segments.append((m.group(1), m.group(2)))
        i = m.end()
    if not segments:
        return None
    name, suffix = segments[0]
    if decls.is_type(name) and decls.type_of(name, pos) is None:
        typ = name
        if suffix:
            return None
    else:
        typ = decls.type_of(name, pos)
        if typ is None:
            return None
        typ = apply_suffix(typ, suffix, False)
    for name, suffix in segments[1:]:
        if typ is None:
            return None
        base = typ.split('.')[-1]
        members = decls.members_of(base)
        if not members or name.lower() not in members:
            return None
        typ = apply_suffix(members[name.lower()], suffix, True)
    return typ


def apply_suffix(typ, suffix, member):
    """Index [i] auf ein Array: Elementtyp; Aufruf (…) ändert nichts (Funktionsergebnis steht schon im Typ)."""
    for part in re.findall(r'\[[^\]]*\]|\((?:[^()]|\([^()]*\))*\)', suffix or ''):
        if part.startswith('['):
            element = element_type(typ)
            if element is None:
                # Indizierte Eigenschaft: Typ ist schon der Elementtyp.
                if not member:
                    return None
                continue
            typ = element
    return typ


def kind_of_type(typ, decls):
    """Art zu einem Typnamen oder None."""
    if typ is None:
        return None
    t = typ.lower()
    if t.startswith('system.'):
        t = t[7:]
    if t in STRING_TYPES:
        return 'string'
    if t in INT_TYPES:
        return 'int'
    if t in BOOL_TYPES:
        return 'bool' if t == 'boolean' else None
    if t in FLOAT_TYPES:
        return 'float'
    if t in GENERIC_ORDINAL:
        return 'T:' + GENERIC_ORDINAL[t]
    if t in decls.record_types:
        return 'record'
    if t in decls.enum_types or t in decls.set_types:
        return 'T:' + typ
    if t in decls.class_types:
        return 'object'
    if t.startswith('i') and len(t) > 1 and typ[1:2].isupper():
        return 'interface'
    return None


def is_constant(expr, decls=None):
    e = strip_parens(expr)
    if decls is not None and RE_IDENT.match(e) and e.lower() in decls.enum_values and decls.type_of(e, 1 << 30) is None:
        return True
    if e.startswith("'") or e.startswith('#'):
        return True
    if RE_FLOAT_LIT.match(e) or RE_INT_LIT.match(e):
        return True
    if e.lower() in ('true', 'false', 'nil'):
        return True
    if e.startswith('[') and e.endswith(']'):
        return True
    if RE_IDENT.match(e) and re.match(r'^c[A-Z]', e):
        return True
    if RE_QUALIFIED.match(e):
        last = e.rsplit('.', 1)[1]
        first = e.split('.', 1)[0]
        if re.match(r'^c[A-Z]', last):
            return True
        # TAufzaehlung.Wert (scoped enum): erster Teil ein T-Typ, letzter Teil groß, kein Aufruf.
        if re.match(r'^T[A-Z]', first) and e.count('.') == 1 and last[:1].isupper():
            return True
    if e.startswith('-') or e.startswith('+'):
        return is_constant(e[1:], decls)
    return False


def guess_kind(expr, pos, decls):
    """Art eines Ausdrucks: string/int/bool/float/T:…/record/object/interface oder None."""
    e = strip_parens(expr)
    low = e.lower()
    if e.startswith("'") or e.startswith('#'):
        # Ein Zeichen kann auch Char sein; längere Literale sind sicher string.
        if re.match(r"^'(?:[^']|'')'$", e) or re.match(r'^#\$?[0-9A-Fa-f]+$', e):
            return 'charlit'
        return 'strlit'
    if low in ('true', 'false'):
        return 'boollit'
    if RE_INT_LIT.match(e):
        return 'intlit'
    if RE_FLOAT_LIT.match(e):
        return 'floatlit'
    if e.startswith('['):
        return 'setlit'
    m = re.match(r'^(Integer|Int64|UInt64|Cardinal|NativeInt|NativeUInt|Double|string|Boolean|Char|Byte|Word|Pointer)'
                 r'\s*\(', e, re.I)
    if m and find_close(e, m.end() - 1) == len(e) - 1:
        return kind_of_type(m.group(1), decls)
    m = re.match(r'^([A-Za-z_][\w.]*)\s*\(', e)
    if m and find_close(e, m.end() - 1) == len(e) - 1:
        name = m.group(1).lower()
        parts = name.split('.')
        if len(parts) == 2 and parts[1] == 'create':
            if parts[0] in decls.record_types:
                return 'record'
            if parts[0] in decls.class_types:
                return 'object'
        if name in KNOWN_FUNCS:
            return KNOWN_FUNCS[name]
        last = name.rsplit('.', 1)[-1]
        if last in KNOWN_MEMBERS and KNOWN_MEMBERS[last]:
            return KNOWN_MEMBERS[last]
        return kind_of_type(decls.type_of(last, pos), decls)
    if RE_IDENT.match(e):
        local = decls.type_of(e, pos)
        values = decls.enum_values.get(low)
        if local is None and values and len(values) == 1:
            # Wert einer Aufzählung ohne Bereichsangabe (wrSignaled).
            return 'enumconst:' + next(iter(values))
        return kind_of_type(local, decls)
    if RE_QUALIFIED.match(e) and e.count('.') == 1 and e.split('.', 1)[0].lower() in decls.enum_types:
        return 'enumconst:' + decls.enum_types[e.split('.', 1)[0].lower()]
    path_type = type_of_path(e, pos, decls)
    if path_type is not None:
        k = kind_of_type(path_type, decls)
        if k:
            return k
    if RE_QUALIFIED.match(e) or re.match(r'^[\w.\[\]()\s,^]+$', e):
        # Feldzugriff X.Y.Z bzw. mit Index: Typ des letzten Namens, falls in der Unit deklariert.
        m = re.search(r'([A-Za-z_]\w*)\s*(\[[^\]]*\])?\s*$', e)
        if m:
            last = m.group(1).lower()
            if m.group(2) is None and last in KNOWN_MEMBERS and KNOWN_MEMBERS[last]:
                return KNOWN_MEMBERS[last]
            k = kind_of_type(decls.type_of(last, pos), decls)
            if k:
                return k
        if RE_QUALIFIED.match(e):
            first, last = e.split('.', 1)[0], e.rsplit('.', 1)[1]
            if first.lower() in decls.enum_types:
                return 'enumconst:' + decls.enum_types[first.lower()]
            if re.match(r'^T[A-Z]', first) and e.count('.') == 1 and last[:1].isupper():
                return 'enumguess:' + first
    return None


def combine(kl, kr):
    """Gemeinsame Art beider Seiten; 'sure' gibt an, ob die Art belastbar ist."""
    # Sichere Literale bestimmen die Art allein: Wert einer Aufzählung (der Vergleich übersetzt nur mit demselben
    # Typ), String mit mehr als einem Zeichen, True/False.
    for a, b in ((kl, kr), (kr, kl)):
        if a and a.startswith('enumconst:'):
            typ = a.split(':', 1)[1]
            # Der Vergleich übersetzt nur, wenn die andere Seite denselben Aufzählungstyp hat.
            return 'T:' + typ, True
    for a, b in ((kl, kr), (kr, kl)):
        if a == 'strlit' and b in (None, 'string', 'strlit', 'charlit'):
            return 'string', True
        if a == 'boollit' and b in (None, 'bool', 'boollit'):
            return 'bool', True
    if kl == 'charlit' and kr == 'charlit':
        return 'string', True
    kl = {'charlit': None, 'strlit': 'string', 'boollit': 'bool'}.get(kl, kl) if kl in ('charlit', 'strlit', 'boollit') else kl
    kr = {'charlit': None, 'strlit': 'string', 'boollit': 'bool'}.get(kr, kr) if kr in ('charlit', 'strlit', 'boollit') else kr
    ks = {kl, kr}
    if None in ks:
        other = kl if kr is None else kr
        # Nur ein Literal bekannt: Strings eindeutig, Zahlen nicht (Integer? Int64? Aufzählung?).
        if other == 'string':
            return 'string', False
        if other == 'bool':
            return 'bool', False
        if other and other.startswith('enumguess:'):
            return 'T:' + other.split(':', 1)[1], False
        if other and other.startswith('T:'):
            return other, False
        return None, False
    if kl == kr:
        if kl == 'intlit':
            return 'int', True
        if kl == 'floatlit':
            return 'float', True
        if kl.startswith('enumguess:'):
            return 'T:' + kl.split(':', 1)[1], False
        return kl, True
    if ks <= {'int', 'intlit'}:
        return 'int', True
    if ks <= {'float', 'floatlit', 'intlit'}:
        return 'float', True
    for k in ks:
        if k and k.startswith('T:') and (ks - {k}) <= {'intlit', 'setlit'}:
            return k, True
        if k and k.startswith('enumguess:') and (ks - {k}) <= {None}:
            return 'T:' + k.split(':', 1)[1], False
    enum = [k for k in ks if k and k.startswith('enumguess:')]
    typed = [k for k in ks if k and k.startswith('T:')]
    if enum and typed and enum[0].split(':', 1)[1].lower() == typed[0][2:].lower():
        return typed[0], True
    if enum and not typed:
        return 'T:' + enum[0].split(':', 1)[1], False
    return None, False


# ---------------------------------------------------------------------------------------------- Umstellen

class Site:
    def __init__(self, path, text, start, open_paren, close, method, prefix):
        self.path = path
        self.start = start
        self.close = close
        self.method = method  # IsTrue / IsFalse
        self.prefix = prefix
        self.line = text.count('\n', 0, start) + 1
        self.col = start - (text.rfind('\n', 0, start) + 1) + 1
        inner = text[open_paren + 1:close]
        args = split_top(inner, [','])
        self.condition = args[0][0]
        # Rest inkl. führendem Komma und Leerraum unverändert übernehmen.
        self.rest = inner[len(args[0][0]):]
        self.kind = None
        self.sure = False
        self.form = None  # (Methode, Argumente)
        self.reason = ''


def analyse(site, text, decls):
    """Bestimmt Form und vermutete Art; liefert False, wenn kein Fall der Regel."""
    cond = strip_parens(site.condition)
    positive = site.method.lower() == 'istrue'
    while re.match(r'^not\b', cond, re.I):
        cond = strip_parens(cond[3:])
        positive = not positive
    m = re.match(r'^Assigned\s*\(', cond, re.I)
    if m and find_close(cond, m.end() - 1) == len(cond) - 1:
        site.form = ('null', not positive, cond[m.end():-1].strip(), None)
        return True
    cmp = split_compare(cond)
    if cmp is None:
        return False
    left, op, right = cmp
    equal = (op == '=') == positive
    if right.lower() == 'nil' or left.lower() == 'nil':
        value = left if right.lower() == 'nil' else right
        site.form = ('null', equal, value, None)
        return True
    expected, actual = right, left
    if is_constant(left, decls) and not is_constant(right, decls):
        expected, actual = left, right
    site.form = ('equal', equal, expected, actual)
    return True


def guess(site, decls):
    kind, _, expected, actual = site.form
    if kind == 'null':
        k = guess_kind(expected, site.start, decls)
        typ = None
        value = strip_parens(expected)
        typ = type_of_path(value, site.start, decls)
        m = re.search(r'([A-Za-z_]\w*)\s*(\(\s*\))?$', value)
        if typ is None and (m and not value.endswith(')') or (m and m.group(2))):
            typ = decls.type_of(m.group(1), site.start)
        if typ is not None:
            k = kind_of_type(typ, decls) or k
        base = (typ or '').split('.')[-1].split('<')[0].lower()
        if base in decls.proc_types or (typ and re.search(r'(Proc|Func|Event|Callback|Handler|Provider)$', typ)):
            site.kind, site.sure, site.reason = 'keep', True, 'Methodenzeiger/-referenz: IsNull passt nicht'
        elif k in ('object', 'interface') or (typ and typ.lower() in ('pointer', 'tobject', 'iinterface')):
            site.kind, site.sure = 'null', True
        elif typ and (re.match(r'^(TArray<|array\b|TBytes$)', typ, re.I) or typ.lower().endswith('array')):
            site.kind, site.sure, site.reason = 'keep', True, 'dynamisches Array: Länge prüfen (AreEqual(0, Integer(Length(…))))'
        elif typ and re.match(r'^[TIP][A-Z]\w*$', typ) and kind_of_type(typ, decls) not in ('record', 'string', 'int'):
            # Mit nil vergleichbar und weder Record, Array noch Methodenzeiger: Klasse, Interface oder Zeiger.
            site.kind, site.sure = 'null', True
        else:
            site.kind, site.sure = 'null', False
        return
    kl = guess_kind(expected, site.start, decls)
    kr = guess_kind(actual, site.start, decls)
    enum = [k for k in (kl, kr) if k and k.startswith('enumconst:')]
    if enum:
        site.kind, site.sure = 'T:' + enum[0].split(':', 1)[1], True
        return
    if 'record' in (kl, kr):
        site.kind, site.sure, site.reason = 'keep', False, 'Record: feldweise vergleichen'
        return
    if 'object' in (kl, kr) or 'interface' in (kl, kr):
        site.kind, site.sure = 'same', kl == kr
        return
    k, sure = combine(kl, kr)
    if k == 'setlit':
        k, sure = None, False
    if k == 'float':
        k = 'float:' + DEFAULT_TOLERANCE
    site.kind, site.sure = k, sure


def int_arg(expr):
    e = expr.strip()
    if COUNT_LIKE.match(e) and find_close(e, e.index('(')) == len(e) - 1:
        return 'Integer(' + e + ')'
    return e


def render(site, kind):
    """Neuer Aufruftext oder None, wenn die Art keine Form ergibt."""
    form, value, expected, actual = site.form
    p = site.prefix
    if kind == 'keep' or kind is None:
        return None
    if form == 'null':
        if kind not in ('null',):
            return None
        method = 'IsNull' if value else 'IsNotNull'
        return '{}.{}({}{})'.format(p, method, expected, site.rest)
    equal = value
    if kind == 'same':
        method = 'AreSame' if equal else 'AreNotSame'
        return '{}.{}({}, {}{})'.format(p, method, expected.strip(), actual.strip(), site.rest)
    if kind == 'bool':
        for lit, other in ((expected, actual), (actual, expected)):
            if lit.strip().lower() in ('true', 'false'):
                truth = (lit.strip().lower() == 'true') == equal
                return '{}.{}({}{})'.format(p, 'IsTrue' if truth else 'IsFalse', other.strip(), site.rest)
        method = 'AreEqual<Boolean>' if equal else 'AreNotEqual<Boolean>'
        return '{}.{}({}, {}{})'.format(p, method, expected.strip(), actual.strip(), site.rest)
    method = 'AreEqual' if equal else 'AreNotEqual'
    if kind == 'string':
        return '{}.{}({}, {}{})'.format(p, method, expected.strip(), actual.strip(), site.rest)
    if kind == 'int':
        return '{}.{}({}, {}{})'.format(p, method, int_arg(expected), int_arg(actual), site.rest)
    if kind.startswith('float'):
        if not equal:
            return None
        tol = kind.split(':', 1)[1] if ':' in kind else DEFAULT_TOLERANCE
        return '{}.AreEqual(Double({}), Double({}), {}{})'.format(p, expected.strip(), actual.strip(), tol, site.rest)
    if kind.startswith('T:'):
        return '{}.{}<{}>({}, {}{})'.format(p, method, kind[2:], expected.strip(), actual.strip(), site.rest)
    raise SystemExit('Unbekannte Art: ' + kind)


def wrap(text, start, close, new):
    """Bricht eine zu lange erste Zeile des neuen Aufrufs nach dem ersten Argument um."""
    line_start = text.rfind('\n', 0, start) + 1
    indent = re.match(r'[ \t]*', text[line_start:]).group(0)
    first = new.split('\n', 1)[0]
    after = ''
    if '\n' not in new:
        line_end = text.find('\n', close)
        after = text[close + 1:len(text) if line_end < 0 else line_end].rstrip('\r')
    if len(text[line_start:start]) + len(first) + len(after) <= MAX_LINE:
        return new
    open_paren = new.index('(')
    args = split_top(new[open_paren + 1:], [', '])
    if len(args) < 2:
        return new
    head = new[:open_paren + 1] + args[0][0] + ','
    tail = new[len(head):].lstrip()
    return head + '\n' + indent + '  ' + tail


def scan(path, text, glob=None):
    decls = Declarations(text, glob)
    mask = code_mask(text)
    sites = []
    for m in RE_CALL.finditer(text):
        if not mask[m.start()]:
            continue
        open_paren = m.end() - 1
        close = find_close(text, open_paren)
        if close < 0:
            continue
        site = Site(path, text, m.start(), open_paren, close, m.group(2), m.group(1))
        if analyse(site, text, decls):
            guess(site, decls)
            sites.append(site)
    return sites


def is_test_unit(text):
    return re.search(r'\bDUnitX\.TestFramework\b', text) is not None


def files_of(paths):
    for p in paths:
        if os.path.isdir(p):
            for root, _, names in os.walk(p):
                for n in sorted(names):
                    if n.lower().endswith('.pas'):
                        yield os.path.join(root, n)
        else:
            yield p


def read(path):
    with open(path, 'rb') as f:
        raw = f.read()
    bom = raw.startswith(b'\xef\xbb\xbf')
    return raw[3:].decode('utf-8') if bom else raw.decode('utf-8'), bom


def load_kinds(path):
    kinds = {}
    if not path:
        return kinds
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.split('#', 1)[0].strip()
            if not line:
                continue
            where, kind = line.rsplit(None, 1)
            kinds[os.path.normpath(where)] = kind
    return kinds


def kind_for(site, kinds):
    key_col = os.path.normpath('{}:{}:{}'.format(site.path, site.line, site.col))
    key_line = os.path.normpath('{}:{}'.format(site.path, site.line))
    if key_col in kinds:
        return kinds[key_col], True
    if key_line in kinds:
        return kinds[key_line], True
    return site.kind, site.sure


def one_line(s):
    return re.sub(r'\s+', ' ', s).strip()


def main():
    parser = argparse.ArgumentParser(description='IsTrue-Vergleiche in DUnitX-Tests umstellen (#2197)')
    parser.add_argument('mode', choices=['list', 'apply'])
    parser.add_argument('paths', nargs='+')
    parser.add_argument('--kinds', help='Artendatei: <Pfad>:<Zeile>[:<Spalte>] <Art>')
    parser.add_argument('--with-guesses', action='store_true',
                        help='auch vermutete Arten (in der Liste mit ?) umstellen; danach übersetzen und prüfen')
    args = parser.parse_args()
    kinds = load_kinds(args.kinds)
    glob = GlobalIndex(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    total = changed = 0
    open_sites = []
    for path in files_of(args.paths):
        try:
            text, bom = read(path)
        except UnicodeDecodeError:
            continue
        if not is_test_unit(text):
            continue
        sites = scan(path, text, glob)
        total += len(sites)
        if args.mode == 'list':
            for s in sites:
                k, sure = kind_for(s, kinds)
                mark = '' if sure else '?'
                print('{}:{}:{}\t{}{}\t{}\t{}'.format(s.path, s.line, s.col, k or '?', mark if k else '',
                                                      one_line(s.condition), s.reason))
            continue
        new_text = text
        for s in reversed(sites):
            k, sure = kind_for(s, kinds)
            if (not args.with_guesses and not sure) or not k:
                open_sites.append((s, k))
                continue
            new = render(s, k)
            if new is None:
                open_sites.append((s, k))
                continue
            new = wrap(new_text, s.start, s.close, new)
            new_text = new_text[:s.start] + new + new_text[s.close + 1:]
            changed += 1
        if new_text != text:
            crlf = '\r\n' in text
            if crlf:
                new_text = new_text.replace('\r\n', '\n').replace('\n', '\r\n')
            with open(path, 'wb') as f:
                f.write(b'\xef\xbb\xbf' + new_text.encode('utf-8'))
    if args.mode == 'apply':
        for s, k in sorted(open_sites, key=lambda x: (x[0].path, x[0].line)):
            print('offen\t{}:{}:{}\t{}\t{}\t{}'.format(s.path, s.line, s.col, k or '?', one_line(s.condition),
                                                     s.reason))
        print('{} Fundstellen, {} umgestellt, {} offen'.format(total, changed, len(open_sites)), file=sys.stderr)
    else:
        print('{} Fundstellen'.format(total), file=sys.stderr)


if __name__ == '__main__':
    main()
