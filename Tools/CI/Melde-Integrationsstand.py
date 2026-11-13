#!/usr/bin/env python3
"""Meldet, wenn eine Prüfung auf main-merging rot wird, und schließt die Meldung, sobald sie wieder grün ist.

Aufruf am Ende eines Workflows (Job „melden“ in package-dependencies.yml und linux-server.yml), nur bei Pushes auf
main-merging:

    python3 Tools/CI/Melde-Integrationsstand.py --workflow "<Name>" --ergebnis success|failure|cancelled

Rot: Je Workflow ein offenes Issue mit Label „main-merging rot“ (neu oder mit weiterem Kommentar) und ein Kommentar
am Pull Request, dessen Merge den Stand erzeugt hat. Nach docs/Zusammenfuehren.md behebt ihn dieser Pull Request.
Grün: Liegt der rote Stand vor dem grünen, wird das Issue mit Verweis auf den grünen Lauf geschlossen.

Umgebung: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA, GITHUB_SERVER_URL, GITHUB_RUN_ID.
"""

import argparse
import json
import os
import re
import subprocess
import sys

LABEL = 'main-merging rot'


def gh(*args, eingabe=None, check=True):
    ergebnis = subprocess.run(['gh', *args], capture_output=True, text=True, encoding='utf-8', input=eingabe)
    if check and ergebnis.returncode != 0:
        sys.stderr.write(ergebnis.stderr)
        raise SystemExit(f'gh {" ".join(args)} fehlgeschlagen')
    return ergebnis


def api(pfad, *args, check=True):
    ergebnis = gh('api', pfad, *args, check=check)
    return json.loads(ergebnis.stdout) if ergebnis.returncode == 0 and ergebnis.stdout.strip() else None


def marke(workflow, sha):
    return f'<!-- integrationsstand workflow="{workflow}" sha="{sha}" -->'


def offenes_issue(repo, workflow):
    for issue in api(f'repos/{repo}/issues?state=open&per_page=100&labels={LABEL.replace(" ", "%20")}') or []:
        treffer = re.search(r'<!-- integrationsstand workflow="([^"]*)" sha="([0-9a-f]+)" -->', issue.get('body') or '')
        if treffer and treffer.group(1) == workflow:
            return issue, treffer.group(2)
    return None, None


def verursacher(repo, sha):
    for pr in api(f'repos/{repo}/commits/{sha}/pulls', check=False) or []:
        if pr.get('merged_at'):
            return pr
    return None


def kommentieren(repo, nummer, text):
    gh('api', f'repos/{repo}/issues/{nummer}/comments', '-F', 'body=@-', eingabe=text)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--workflow', required=True)
    parser.add_argument('--ergebnis', required=True)
    args = parser.parse_args()

    repo = os.environ['GITHUB_REPOSITORY']
    sha = os.environ['GITHUB_SHA']
    lauf = f'{os.environ.get("GITHUB_SERVER_URL", "https://github.com")}/{repo}/actions/runs/{os.environ["GITHUB_RUN_ID"]}'
    kurz = sha[:8]
    issue, roter_sha = offenes_issue(repo, args.workflow)

    if args.ergebnis == 'success':
        if not issue:
            return 0
        vergleich = api(f'repos/{repo}/compare/{roter_sha}...{sha}', check=False)
        if not vergleich or vergleich.get('status') not in ('ahead', 'identical'):
            return 0  # älterer Lauf, der nach dem roten fertig wurde
        kommentieren(repo, issue['number'], f'Wieder grün mit {kurz}: {lauf}')
        gh('api', '-X', 'PATCH', f'repos/{repo}/issues/{issue["number"]}', '-f', 'state=closed',
           '-f', 'state_reason=completed')
        return 0
    if args.ergebnis != 'failure':
        return 0

    pr = verursacher(repo, sha)
    herkunft = f'#{pr["number"]} ({pr["title"]})' if pr else f'Commit {kurz}'
    if issue:
        kommentieren(repo, issue['number'], f'Weiterhin rot mit {kurz}, zuletzt gemergt: {herkunft}. Lauf: {lauf}')
    else:
        gh('api', f'repos/{repo}/labels', '-f', f'name={LABEL}', '-f', 'color=b60205',
           '-f', 'description=Prüfung auf main-merging gescheitert', check=False)
        text = '\n'.join([
            marke(args.workflow, sha),
            f'„{args.workflow}“ scheitert auf `main-merging` mit {kurz}.', '',
            f'- Zuletzt gemergt: {herkunft}',
            f'- Lauf: {lauf}', '',
            'Solange `main-merging` rot ist, scheitert dieselbe Prüfung in jedem Pull Request, der den Fehler erbt. '
            'Nach docs/Zusammenfuehren.md behebt das der zuletzt gemergte Pull Request (Folge-PR nach main-merging). '
            'Das Issue schließt sich, sobald der Workflow auf main-merging wieder grün ist.'])
        gh('api', f'repos/{repo}/issues', '-f', f'title=main-merging rot: {args.workflow}', '-f', f'labels[]={LABEL}',
           '-F', 'body=@-', eingabe=text)
    if pr and not issue:
        # Nur der Pull Request, mit dem es rot wurde; spätere erben den Fehler nur.
        kommentieren(repo, pr['number'],
                     f'Nach dem Merge dieses Pull Requests scheitert „{args.workflow}“ auf `main-merging`: {lauf}\n\n'
                     'Bitte mit einem Folge-PR nach main-merging beheben (docs/Zusammenfuehren.md); bis dahin '
                     'scheitert die Prüfung auch in anderen Pull Requests.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
