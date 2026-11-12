#!/usr/bin/env bash
# Selbstprüfung je Plugin-Package (Code-Review A-101): prüft jedes Packages/Atlas.IDE.*/<Package>.dproj mit der
# atlas.json und der atlas-baseline.json des Packages. Jeder Treffer außerhalb der Baseline ist neu und lässt das
# Skript scheitern, auch Hinweise.
#
# Aufruf: Tools/Linux/Check-PluginPackages.sh [<AtlasServer>] [<Package> ...]
#
#   <AtlasServer>  Programm (Standard: Output/Linux64/Bin/AtlasServer, sonst AtlasServer aus PATH)
#   <Package>      nur diese Packages, z. B. Atlas.IDE.Designer (Standard: alle)
#
# Neue Treffer beheben. Nur wenn sich die Konfiguration ändert (Tools/Update-PackageConfigs.ps1), die Baseline des
# Packages neu erzeugen: AtlasServer --check Packages/<Package>/<Package>.dproj --update-baseline
#
# Ergebnis: Exit-Code 0 ohne neue Treffer, 1 mit neuen Treffern, 3 bei einem Fehler des Laufs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVER=""
if [[ $# -gt 0 && "$1" != Atlas.IDE.* ]]; then
  SERVER="$1"
  shift
elif [[ -x "$ROOT/Output/Linux64/Bin/AtlasServer" ]]; then
  SERVER="$ROOT/Output/Linux64/Bin/AtlasServer"
else
  SERVER="AtlasServer"
fi

PACKAGES=("$@")
if [[ ${#PACKAGES[@]} -eq 0 ]]; then
  for DIR in "$ROOT"/Packages/Atlas.IDE.*/; do
    NAME="$(basename "$DIR")"
    [[ -f "$DIR$NAME.dproj" ]] && PACKAGES+=("$NAME")
  done
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILED=0
for NAME in "${PACKAGES[@]}"; do
  PROJECT="$ROOT/Packages/$NAME/$NAME.dproj"
  if ! "$SERVER" --check "$PROJECT" --format json --fail-on never --output "$WORK/$NAME.json" 2> "$WORK/$NAME.err"; then
    cat "$WORK/$NAME.err" >&2
    echo "$NAME: Prüflauf gescheitert" >&2
    exit 3
  fi
  if ! python3 - "$WORK/$NAME.json" "$NAME" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
name = sys.argv[2]
count = 0
for item in data['files']:
    for finding in item['findings']:
        count += 1
        line = finding['range']['start']['line'] + 1
        print(f"::error file=Packages/{name}/{item['path']},line={line}::{finding['rule']}: {finding['message']}",
              file=sys.stderr)
print(f"{name}: {count} neue Treffer in {data['summary']['files']} Dateien", file=sys.stderr)
sys.exit(1 if count else 0)
PY
  then
    FAILED=1
  fi
done
exit "$FAILED"
