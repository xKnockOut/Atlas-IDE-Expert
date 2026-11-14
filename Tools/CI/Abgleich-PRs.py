#!/usr/bin/env python3
"""Offene Pull Requests nach main-merging mit dem Integrationsbranch abgleichen (Workflow pr-abgleich.yml).

GitHub führt einen Pull Request mit Auto-Merge zusammen, sobald die Pflichtprüfung grün ist; er muss dafür nicht auf
dem neuesten Stand sein. Zwei Fälle bleiben aber liegen, ohne dass es jemand merkt:

- Konflikt mit main-merging: GitHub legt keinen Merge-Commit an, die CI läuft nicht, Auto-Merge wartet stumm.
- Beide Seiten ändern Quellen erzeugter Dateien (Schema, Profile, Regelkatalog): Textlich passt alles, aber die
  erzeugten Dateien passen nach dem Merge zu keiner Seite und main-merging wird rot.

Für diese Pull Requests mergt das Skript main-merging mit Tools/Merge-Integration.py ein (Stand von main-merging,
nicht der des Pull Requests) und pusht das Ergebnis auf den Branch des Pull Requests. Bleibt ein echter Konflikt,
bekommt der Pull Request das Label „Konflikt mit main-merging“ und einen Kommentar mit den Dateien. Alle anderen
Pull Requests bleiben unangetastet: ein Push startet die CI neu und zwingt den Thread, seinen Branch einzuholen.

Bearbeitet werden nur Pull Requests aus diesem Repository von Branches claude/…, keine Entwürfe.

Umgebung: GH_TOKEN (gh), GITHUB_REPOSITORY, optional ZIEL (Vorgabe main-merging) und PUSHEN=1, wenn der Checkout
mit einem Token (Secret ABGLEICH_TOKEN) pushen darf, dessen Pushes die Prüfungen des Pull Requests normal starten.
Ohne das Token pusht das Skript nicht: Ein Push mit GITHUB_TOKEN erzeugt Pull-Request-Läufe, die auf Freigabe warten,
und per workflow_dispatch nachgestartete Prüfungen zählen für Auto-Merge nicht (der Pull Request bleibt „blocked“,
obwohl alle Pflichtprüfungen grün sind). Dann meldet das Skript am Pull Request, dass der Thread selbst abgleicht.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.parse

LABEL = 'Konflikt mit main-merging'
MARKE = '<!-- pr-abgleich -->'
# Quellen erzeugter Dateien, wie in Tools/Merge-Integration.py.
QUELLEN_ERZEUGTER = ('schemas/', 'Setup/Profile/', 'Packages/Atlas.Common/Katalog/')


def lauf(*args, check=True, eingabe=None):
    ergebnis = subprocess.run(list(args), capture_output=True, text=True, encoding='utf-8', input=eingabe)
    if check and ergebnis.returncode != 0:
        sys.stderr.write(ergebnis.stdout + ergebnis.stderr)
        raise SystemExit(f'{" ".join(args)} fehlgeschlagen ({ergebnis.returncode})')
    return ergebnis


def git(*args, check=True):
    return lauf('git', *args, check=check)


def gh_api(pfad, *args, check=True):
    ergebnis = lauf('gh', 'api', pfad, *args, check=check)
    if ergebnis.returncode != 0 or not ergebnis.stdout.strip():
        return None
    return json.loads(ergebnis.stdout)


def gh_api_seiten(pfad):
    # --paginate liefert je Seite ein JSON-Array; --slurp fasst sie zusammen.
    seiten = json.loads(lauf('gh', 'api', '--paginate', '--slurp', pfad).stdout)
    return [eintrag for seite in seiten for eintrag in seite]


def beide_aendern(basis, eigen, fremd, praefixe):
    eigene = git('diff', '--name-only', basis, eigen).stdout.splitlines()
    fremde = git('diff', '--name-only', basis, fremd).stdout.splitlines()
    return any(p.startswith(praefixe) for p in eigene) and any(p.startswith(praefixe) for p in fremde)


def label_anlegen(repo):
    lauf('gh', 'api', f'repos/{repo}/labels', '-f', f'name={LABEL}', '-f', 'color=d93f0b',
         '-f', 'description=Automatischer Abgleich mit main-merging scheitert; Thread muss den Konflikt lösen',
         check=False)


def label_setzen(repo, nummer, an, labels):
    if an and LABEL not in labels:
        label_anlegen(repo)
        lauf('gh', 'api', f'repos/{repo}/issues/{nummer}/labels', '-f', f'labels[]={LABEL}', check=False)
    elif not an and LABEL in labels:
        lauf('gh', 'api', '-X', 'DELETE', f'repos/{repo}/issues/{nummer}/labels/{urllib.parse.quote(LABEL)}', check=False)


def kommentieren(repo, nummer, text):
    """Schreibt den Kommentar nur, wenn der letzte des Abgleichs anders lautet (keine Wiederholung je Push)."""
    text = MARKE + '\n' + text
    kommentare = gh_api_seiten(f'repos/{repo}/issues/{nummer}/comments?per_page=100')
    eigene = [k for k in kommentare if k.get('body', '').startswith(MARKE)]
    if eigene and eigene[-1]['body'].strip() == text.strip():
        return
    lauf('gh', 'api', f'repos/{repo}/issues/{nummer}/comments', '-F', 'body=@-', eingabe=text)


def konflikt_text(ziel, dateien, grund):
    zeilen = [f'**Konflikt mit `{ziel}`.** {grund}', '',
              'Solange der Konflikt besteht, legt GitHub keinen Merge-Commit an: Die CI läuft nicht und das '
              'automatische Zusammenführen wartet.', '']
    if dateien:
        zeilen.append('Offen:')
        zeilen.extend(f'- `{d}`' for d in dateien)
        zeilen.append('')
    zeilen.append('Lösen: `python3 Tools/Merge-Integration.py`, die genannten Stellen von Hand lösen, `git add`, '
                  '`git commit --no-edit`, pushen (docs/Zusammenfuehren.md).')
    return '\n'.join(zeilen)


def offene_dateien(ausgabe):
    dateien = []
    im_block = False
    for zeile in ausgabe.splitlines():
        if zeile.startswith('Offene Konflikte:'):
            im_block = True
        elif im_block and zeile.startswith('  '):
            dateien.append(zeile.strip())
        else:
            im_block = False
    return dateien


def aufraeumen():
    git('merge', '--abort', check=False)
    git('reset', '--hard', '-q', check=False)
    git('clean', '-fdq', check=False)


def gleiche_ab(repo, pr, ziel, skript, pushen, bericht):
    nummer = pr['number']
    branch = pr['head']['ref']
    labels = [l['name'] for l in pr.get('labels', [])]
    git('fetch', '-q', 'origin', f'+refs/heads/{branch}:refs/remotes/origin/{branch}')
    aufraeumen()
    git('checkout', '-q', '-f', '-B', 'pr-abgleich', f'refs/remotes/origin/{branch}')
    ziel_ref = f'refs/remotes/origin/{ziel}'

    if git('merge-base', '--is-ancestor', ziel_ref, 'HEAD', check=False).returncode == 0:
        label_setzen(repo, nummer, False, labels)
        bericht.append(f'#{nummer}: aktuell')
        return
    basis = git('merge-base', 'HEAD', ziel_ref).stdout.strip()
    # Exit-Code 1: Konflikt (git ≥ 2.38).
    konflikt = git('merge-tree', '--write-tree', 'HEAD', ziel_ref, check=False).returncode == 1
    erzeugte = beide_aendern(basis, 'HEAD', ziel_ref, QUELLEN_ERZEUGTER)
    if not konflikt and not erzeugte:
        label_setzen(repo, nummer, False, labels)
        bericht.append(f'#{nummer}: ohne Konflikt, bleibt unverändert')
        return

    ergebnis = lauf(sys.executable, skript, '--ziel', ziel, '--ohne-fetch', check=False)
    ausgabe = ergebnis.stdout + ergebnis.stderr
    print(f'--- #{nummer} ({branch}): Merge-Integration.py Code {ergebnis.returncode}\n{ausgabe}')
    if ergebnis.returncode == 1:
        aufraeumen()
        label_setzen(repo, nummer, True, labels)
        kommentieren(repo, nummer, konflikt_text(ziel, offene_dateien(ausgabe),
                                                 'Der automatische Abgleich hat nicht alle Konflikte gelöst.'))
        bericht.append(f'#{nummer}: Konflikt bleibt ({", ".join(offene_dateien(ausgabe))})')
        return
    if ergebnis.returncode != 0:
        aufraeumen()
        label_setzen(repo, nummer, True, labels)
        kommentieren(repo, nummer, konflikt_text(
            ziel, [], f'Tools/Merge-Integration.py endete mit Code {ergebnis.returncode}:\n\n```\n'
                      + '\n'.join(ausgabe.strip().splitlines()[-15:]) + '\n```'))
        bericht.append(f'#{nummer}: Merge-Integration.py Code {ergebnis.returncode}')
        return

    if not pushen:
        aufraeumen()
        label_setzen(repo, nummer, True, labels)
        kommentieren(repo, nummer, konflikt_text(
            ziel, [], 'Tools/Merge-Integration.py löst ihn ohne Handarbeit; der automatische Abgleich darf ohne das '
                      'Secret `ABGLEICH_TOKEN` nicht selbst pushen. Bitte im Thread abgleichen und pushen.'))
        bericht.append(f'#{nummer}: lösbar, ohne ABGLEICH_TOKEN nur gemeldet')
        return

    # Ohne --force: Hat der Thread inzwischen selbst gepusht, scheitert der Push, und der nächste Lauf versucht es neu.
    push = git('push', 'origin', f'HEAD:refs/heads/{branch}', check=False)
    if push.returncode != 0:
        fehler = push.stderr
        if 'workflow' in fehler and ('permission' in fehler or 'refusing' in fehler):
            label_setzen(repo, nummer, True, labels)
            kommentieren(repo, nummer, konflikt_text(
                ziel, [], 'Der Abgleich ist gelungen, aber der Push wurde abgelehnt: main-merging ändert Dateien '
                          'unter `.github/workflows`, und das Token des Abgleichs darf keine Workflows ändern '
                          '(Secret `ABGLEICH_TOKEN` fehlt oder hat das Recht nicht).'))
            bericht.append(f'#{nummer}: Push abgelehnt (Workflow-Dateien)')
        else:
            bericht.append(f'#{nummer}: Push gescheitert, nächster Lauf ({fehler.strip().splitlines()[-1:]})')
        return
    label_setzen(repo, nummer, False, labels)
    art = 'Konflikt' if konflikt else 'erzeugte Dateien'
    bericht.append(f'#{nummer}: abgeglichen ({art}) und gepusht')


def main():
    repo = os.environ['GITHUB_REPOSITORY']
    ziel = os.environ.get('ZIEL', 'main-merging')
    pushen = os.environ.get('PUSHEN') == '1'
    os.chdir(git('rev-parse', '--show-toplevel').stdout.strip())
    git('fetch', '-q', 'origin', f'+refs/heads/{ziel}:refs/remotes/origin/{ziel}')

    # Merge-Helfer im Stand des Ziels, außerhalb des Arbeitsbaums (eine Kopie unter Tools/ wäre untracked).
    ordner = tempfile.mkdtemp(prefix='pr-abgleich-')
    skript = os.path.join(ordner, 'Merge-Integration.py')
    with open(skript, 'w', encoding='utf-8') as datei:
        datei.write(git('show', f'refs/remotes/origin/{ziel}:Tools/Merge-Integration.py').stdout)

    prs = gh_api_seiten(f'repos/{repo}/pulls?state=open&base={ziel}&per_page=100')
    bericht = []
    for pr in sorted(prs, key=lambda p: p['number']):
        if pr['head']['repo'] is None or pr['head']['repo']['full_name'] != repo:
            bericht.append(f'#{pr["number"]}: aus fremdem Repository, übersprungen')
            continue
        if not pr['head']['ref'].startswith('claude/') or pr.get('draft'):
            bericht.append(f'#{pr["number"]}: Entwurf oder kein claude/…-Branch, übersprungen')
            continue
        try:
            gleiche_ab(repo, pr, ziel, skript, pushen, bericht)
        except SystemExit as fehler:
            bericht.append(f'#{pr["number"]}: Fehler im Abgleich: {fehler}')
            aufraeumen()
    shutil.rmtree(ordner, ignore_errors=True)

    zusammenfassung = os.environ.get('GITHUB_STEP_SUMMARY')
    text = '### Abgleich der offenen Pull Requests\n\n' + '\n'.join(f'- {z}' for z in bericht) + '\n'
    sys.stderr.write(text)
    if zusammenfassung:
        with open(zusammenfassung, 'a', encoding='utf-8') as datei:
            datei.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
