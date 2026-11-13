#!/usr/bin/env python3
"""Integrationsbranch (Vorgabe main-merging) in den aktuellen Branch mergen und die
wiederkehrenden Konflikte selbst lösen.

Parallele Pull Requests ändern immer dieselben Stellen. Dieses Skript löst davon, was
sich ohne Urteil lösen lässt, und lässt alles andere als Konflikt stehen:

- Erzeugte Dateien (Einstellungsdoku, Regeldoku, Schema- und Katalog-Units): Stand des
  Integrationsbranches übernehmen und danach mit Update-ConfigDoc.ps1 und
  Update-RuleCatalog.ps1 neu erzeugen. Von Hand gelöst wären sie sofort wieder veraltet.
- Reine Ergänzungen beider Seiten an derselben Stelle (Listen in .dpr/.dpk/.dproj,
  Tools/Linux/FpcTests.txt, Tabellenzeilen und Aufzählungen in Markdown): beide behalten,
  erst die eigenen Zeilen, dann die fremden; doppelte Zeilen nur einmal.
- Zeilen in Markdown, die sich nur in Zahlen unterscheiden (Regelzahlen im README):
  Stand des Integrationsbranches, die Zahlen erzeugt Update-RuleCatalog.ps1 neu.

Was übrig bleibt (geänderte Zeilen auf beiden Seiten, Quelltext, JSON), meldet das
Skript; der Merge bleibt dann offen.

Aufruf aus dem Wurzelordner des Repositorys:

    python3 Tools/Merge-Integration.py              # main-merging einmergen
    python3 Tools/Merge-Integration.py --ziel main  # anderer Branch
    python3 Tools/Merge-Integration.py --kein-commit
    python3 Tools/Merge-Integration.py --selbsttest

Exit-Code 0: gemergt (oder nichts zu tun), 1: Konflikte bleiben, 2: Dateien müssen noch
neu erzeugt werden (pwsh fehlt), 3: Vorbedingung verletzt.
"""

import argparse
import fnmatch
import os
import re
import shutil
import subprocess
import sys

# Erzeugte Dateien und das Werkzeug, das sie schreibt.
ABGELEITET = [
    ('docs/Konfiguration.md', 'config'),
    ('docs/en/Configuration.md', 'config'),
    ('docs/Einstellungen.md', 'config'),
    ('docs/en/Settings.md', 'config'),
    ('Packages/Atlas.IDE.Base/Source/Core/Settings/Atlas.Core.Settings.SchemaData.pas', 'config'),
    ('Packages/Atlas.IDE.Base/Source/Core/Settings/Atlas.Core.Settings.PluginSchemaData.pas', 'config'),
    ('Packages/Atlas.IDE.Base/Source/Core/Settings/Atlas.Core.Settings.ProfileData.pas', 'config'),
    ('Packages/Atlas.Common/Source/Configuration/Internals/Atlas.Common.Configuration.Internals.ScopeData.pas',
     'config'),
    ('docs/Regeln.md', 'rules'),
    ('docs/en/Rules.md', 'rules'),
    ('Packages/Atlas.Common/Source/Rules/Atlas.Common.Rules.Catalog.Data*.pas', 'rules'),
]

WERKZEUGE = {
    'config': 'Tools/Update-ConfigDoc.ps1',
    'rules': 'Tools/Update-RuleCatalog.ps1',
}

# Dateien, in denen reine Ergänzungen beider Seiten zusammen stehen bleiben dürfen.
ERGAENZBAR = ['*.md', '*.dpr', '*.dpk', '*.dproj', 'Tools/Linux/FpcTests.txt']

# Dateien, in denen Zeilen mit nur anderen Zahlen den Stand des Ziels nehmen.
NUR_ZAHLEN = ['*.md']


def git(*args, check=True, capture=True):
    result = subprocess.run(['git', *args], capture_output=capture, text=True, encoding='utf-8')
    if check and result.returncode != 0:
        sys.stderr.write(result.stderr or '')
        raise SystemExit(f'git {" ".join(args)} fehlgeschlagen ({result.returncode})')
    return result


def passt(pfad, muster):
    return any(fnmatch.fnmatchcase(pfad, m) or fnmatch.fnmatchcase(os.path.basename(pfad), m) for m in muster)


def werkzeug_fuer(pfad):
    for muster, werkzeug in ABGELEITET:
        if fnmatch.fnmatchcase(pfad, muster):
            return werkzeug
    return None


def ohne_zahlen(zeilen):
    return [re.sub(r'\d+', '#', z.rstrip('\r\n')) for z in zeilen]


def loese_bloecke(text, erg, zahlen):
    """Löst Konfliktblöcke (diff3) im Text. Liefert (neuer Text, offen, Zahlen übernommen)."""
    zeilen = text.splitlines(keepends=True)
    aus = []
    offen = 0
    zahlen_genommen = False
    i = 0
    while i < len(zeilen):
        z = zeilen[i]
        if not z.startswith('<<<<<<< '):
            aus.append(z)
            i += 1
            continue
        anfang = i
        teile = {'eigen': [], 'basis': [], 'fremd': []}
        teil = 'eigen'
        i += 1
        ende = None
        while i < len(zeilen):
            z = zeilen[i]
            kern = z.rstrip('\r\n')
            if kern.startswith('||||||| ') or kern == '|||||||':
                teil = 'basis'
            elif kern == '=======':
                teil = 'fremd'
            elif kern.startswith('>>>>>>> '):
                ende = i
                break
            else:
                teile[teil].append(z)
            i += 1
        if ende is None:
            # Unvollständiger Block: unverändert lassen.
            aus.extend(zeilen[anfang:])
            offen += 1
            break
        i = ende + 1
        eigen, basis, fremd = teile['eigen'], teile['basis'], teile['fremd']
        if erg and not basis:
            bekannt = {e.rstrip('\r\n') for e in eigen}
            aus.extend(eigen)
            aus.extend(f for f in fremd if f.rstrip('\r\n') not in bekannt)
            continue
        if zahlen and len(eigen) == len(fremd) and ohne_zahlen(eigen) == ohne_zahlen(fremd):
            aus.extend(fremd)
            zahlen_genommen = True
            continue
        aus.extend(zeilen[anfang:ende + 1])
        offen += 1
    return ''.join(aus), offen, zahlen_genommen


def lies(pfad):
    with open(pfad, 'rb') as datei:
        roh = datei.read()
    bom = roh.startswith(b'\xef\xbb\xbf')
    return roh[3:].decode('utf-8') if bom else roh.decode('utf-8'), bom


def schreib(pfad, text, bom):
    with open(pfad, 'wb') as datei:
        datei.write((b'\xef\xbb\xbf' if bom else b'') + text.encode('utf-8'))


def hole(ziel):
    git('fetch', 'origin', f'+refs/heads/{ziel}:refs/remotes/origin/{ziel}')
    ref = f'refs/remotes/origin/{ziel}'
    # Flacher Klon: so lange vertiefen, bis es eine gemeinsame Basis gibt.
    for tiefe in (200, 1000):
        if git('merge-base', 'HEAD', ref, check=False).returncode == 0:
            return ref
        git('fetch', f'--deepen={tiefe}', 'origin', f'+refs/heads/{ziel}:refs/remotes/origin/{ziel}', check=False)
    if git('merge-base', 'HEAD', ref, check=False).returncode != 0:
        if os.path.exists(os.path.join(git('rev-parse', '--git-dir').stdout.strip(), 'shallow')):
            git('fetch', '--unshallow', 'origin', f'+refs/heads/{ziel}:refs/remotes/origin/{ziel}')
        if git('merge-base', 'HEAD', ref, check=False).returncode != 0:
            raise SystemExit(f'Keine gemeinsame Basis mit {ref}')
    return ref


def selbsttest():
    """Prüft das Lösen der Konfliktblöcke ohne Git (CI)."""
    def block(eigen, basis, fremd):
        return '<<<<<<< HEAD\r\n' + eigen + '||||||| basis\r\n' + basis + '=======\r\n' + fremd + '>>>>>>> ziel\r\n'

    faelle = [
        # Reine Ergänzungen: beide behalten, doppelte einmal.
        ('a\r\n' + block('  F in f,\r\n  G in g,\r\n', '', '  G in g,\r\n  O in o,\r\n') + 'z\r\n', True, False,
         'a\r\n  F in f,\r\n  G in g,\r\n  O in o,\r\nz\r\n', 0, False),
        # Beide ändern dieselbe Zeile: offen.
        (block('x := 2;\r\n', 'x := 1;\r\n', 'x := 3;\r\n'), True, False, None, 1, False),
        # Nur Zahlen verschieden: Stand des Ziels.
        (block('mit 346 Regeln\r\n', 'mit 345 Regeln\r\n', 'mit 347 Regeln\r\n'), True, True,
         'mit 347 Regeln\r\n', 0, True),
        # Text verschieden trotz gleicher Zahl der Zeilen: offen.
        (block('346 Regeln, a\r\n', '345 Regeln\r\n', '347 Regeln, b\r\n'), True, True, None, 1, False),
    ]
    fehler = 0
    for nr, (text, erg, zahlen, erwartet, offen_soll, zahlen_soll) in enumerate(faelle, 1):
        neu, offen, genommen = loese_bloecke(text, erg, zahlen)
        if erwartet is None:
            erwartet = text
        if (neu, offen, genommen) != (erwartet, offen_soll, zahlen_soll):
            print(f'Fall {nr}: erwartet {erwartet!r}/{offen_soll}/{zahlen_soll}, erhalten {neu!r}/{offen}/{genommen}')
            fehler += 1
    for pfad, soll in [('docs/Einstellungen.md', 'config'),
                       ('Packages/Atlas.Common/Source/Rules/Atlas.Common.Rules.Catalog.Data.De.Architecture.pas', 'rules'),
                       ('README.md', None)]:
        if werkzeug_fuer(pfad) != soll:
            print(f'{pfad}: Werkzeug {werkzeug_fuer(pfad)} statt {soll}')
            fehler += 1
    print('Selbsttest ' + ('fehlgeschlagen' if fehler else 'in Ordnung'))
    return 1 if fehler else 0


def main():
    if '--selbsttest' in sys.argv[1:]:
        return selbsttest()
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--ziel', default='main-merging', help='Branch auf origin, der eingemergt wird')
    parser.add_argument('--kein-commit', action='store_true', help='Merge vorbereiten, nicht committen')
    parser.add_argument('--ohne-fetch', action='store_true', help='origin/<ziel> nicht neu holen (Tests)')
    args = parser.parse_args()

    os.chdir(git('rev-parse', '--show-toplevel').stdout.strip())
    if git('status', '--porcelain', '--untracked-files=no').stdout.strip():
        print('Arbeitskopie hat ungesicherte Änderungen; erst committen.')
        return 3

    ref = f'refs/remotes/origin/{args.ziel}' if args.ohne_fetch else hole(args.ziel)
    if git('merge-base', '--is-ancestor', ref, 'HEAD', check=False).returncode == 0:
        print(f'{args.ziel} ist schon enthalten.')
        return 0

    merge = git('-c', 'merge.conflictStyle=diff3', 'merge', '--no-ff', '--no-commit', '-m',
                f'{args.ziel} eingemergt', ref, check=False)
    print(merge.stdout.strip())

    konflikte = [p for p in git('diff', '--name-only', '--diff-filter=U').stdout.splitlines() if p]
    neu_erzeugen = set()
    geloest = []
    offen = []
    for pfad in konflikte:
        werkzeug = werkzeug_fuer(pfad)
        if werkzeug:
            git('checkout', '--theirs', '--', pfad)
            git('add', '--', pfad)
            neu_erzeugen.add(werkzeug)
            geloest.append(f'{pfad} (erzeugt, Stand {args.ziel})')
            continue
        erg = passt(pfad, ERGAENZBAR)
        zahlen = passt(pfad, NUR_ZAHLEN)
        if not (erg or zahlen) or not os.path.isfile(pfad):
            offen.append(pfad)
            continue
        try:
            text, bom = lies(pfad)
        except UnicodeDecodeError:
            offen.append(pfad)
            continue
        neu, rest, zahlen_genommen = loese_bloecke(text, erg, zahlen)
        if neu != text:
            schreib(pfad, neu, bom)
        if zahlen_genommen:
            neu_erzeugen.add('rules')
        if rest:
            offen.append(f'{pfad} ({rest} Stellen)')
        else:
            git('add', '--', pfad)
            geloest.append(pfad)

    # Haben beide Seiten die Quellen geändert (Schema, Regelkatalog), passen die erzeugten Dateien keiner Seite.
    basis = git('merge-base', 'HEAD', ref).stdout.strip()
    eigene = git('diff', '--name-only', basis, 'HEAD').stdout.splitlines()
    fremde = git('diff', '--name-only', basis, ref).stdout.splitlines()

    def beide(*praefixe):
        return any(p.startswith(praefixe) for p in eigene) and any(p.startswith(praefixe) for p in fremde)

    if beide('schemas/', 'Setup/Profile/'):
        neu_erzeugen.add('config')
    if beide('Packages/Atlas.Common/Katalog/'):
        neu_erzeugen.add('rules')

    for zeile in geloest:
        print(f'gelöst: {zeile}')

    pwsh = shutil.which('pwsh')
    fehlt = []
    for werkzeug in sorted(neu_erzeugen):
        skript = WERKZEUGE[werkzeug]
        if not pwsh:
            fehlt.append(f'pwsh {skript}')
            continue
        lauf = subprocess.run([pwsh, '-NoProfile', '-File', skript])
        if lauf.returncode != 0:
            offen.append(f'{skript} meldet Fehler')
    if neu_erzeugen and pwsh:
        git('add', '-u')

    eigener_changelog = git('diff', '-U0', basis, 'HEAD', '--', 'CHANGELOG.md').stdout.splitlines()
    if sum(z.startswith('+- ') for z in eigener_changelog) > sum(z.startswith('-- ') for z in eigener_changelog):
        print('Hinweis: Dieser Branch ändert CHANGELOG.md; Einträge gehören nach changelog.d/ (siehe dortige README.md).')

    if offen:
        print('Offene Konflikte:')
        for pfad in offen:
            print(f'  {pfad}')
        print('Von Hand lösen, git add, dann git commit --no-edit.')
        return 1
    if fehlt:
        print('Erzeugte Dateien noch neu schreiben, dann git add -u und git commit --no-edit:')
        for befehl in fehlt:
            print(f'  {befehl}')
        return 2
    if args.kein_commit:
        print('Merge vorbereitet, nicht committet.')
        return 0
    git('commit', '--no-edit')
    print(f'{args.ziel} eingemergt.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
