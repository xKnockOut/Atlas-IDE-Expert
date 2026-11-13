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
#   Umgebung: ATLAS_CHECK_JOBS (gleichzeitige Prüfläufe, Standard: Zahl der Kerne)
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

# Ein Package prüfen; Ausgabe nach $WORK/<Package>.log, Exit-Code 0/1/3 wie das Skript.
check_package() {
  local NAME="$1"
  local PROJECT="$ROOT/Packages/$NAME/$NAME.dproj"
  if ! "$SERVER" --check "$PROJECT" --format json --fail-on never --output "$WORK/$NAME.json" 2> "$WORK/$NAME.err"; then
    cat "$WORK/$NAME.err"
    echo "$NAME: Prüflauf gescheitert"
    return 3
  fi
  python3 - "$WORK/$NAME.json" "$NAME" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
name = sys.argv[2]
count = 0
for item in data['files']:
    for finding in item['findings']:
        count += 1
        line = finding['range']['start']['line'] + 1
        print(f"::error file=Packages/{name}/{item['path']},line={line}::{finding['rule']}: {finding['message']}")
print(f"{name}: {count} neue Treffer in {data['summary']['files']} Dateien")
sys.exit(1 if count else 0)
PY
}

# Die Packages laufen parallel (so viele wie Kerne); die Ausgaben erscheinen danach in fester Reihenfolge.
JOBS="${ATLAS_CHECK_JOBS:-$(nproc 2>/dev/null || echo 2)}"
declare -A PIDS=()
for NAME in "${PACKAGES[@]}"; do
  while [[ "$(jobs -rp | wc -l)" -ge "$JOBS" ]]; do
    wait -n || true
  done
  check_package "$NAME" > "$WORK/$NAME.log" 2>&1 &
  PIDS[$NAME]=$!
done

FAILED=0
for NAME in "${PACKAGES[@]}"; do
  CODE=0
  wait "${PIDS[$NAME]}" || CODE=$?
  cat "$WORK/$NAME.log" >&2
  if [[ "$CODE" -eq 3 ]]; then
    exit 3
  elif [[ "$CODE" -ne 0 ]]; then
    FAILED=1
  fi
done
exit "$FAILED"
