#!/usr/bin/env bash
# Selbstprüfung je Plugin-Package: prüft jedes Packages/Atlas.IDE.*/<Package>.dproj mit der
# atlas.json und der atlas-baseline.json des Packages. Jeder Treffer außerhalb der Baseline ist neu und lässt das
# Skript scheitern, auch Hinweise.
#
# Aufruf: Tools/Linux/Check-PluginPackages.sh [<AtlasServer>] [--seit <Ref>] [<Package> ...]
#
#   <AtlasServer>  Programm (Standard: Output/Linux64/Bin/AtlasServer, sonst AtlasServer aus PATH)
#   --seit <Ref>   nur Packages, die die Änderungen seit <Ref> betreffen (Pull Request, siehe betroffene_packages)
#   <Package>      nur diese Packages, z. B. Atlas.IDE.Designer (Standard: alle)
#
#   Umgebung: ATLAS_CHECK_JOBS (gleichzeitige Prüfläufe, Standard: Zahl der Kerne)
#             ATLAS_SHARD=<k>/<n> (nur der k-te von n Teilen; die Packages werden nach Zahl ihrer .pas-Dateien
#             verteilt, das größte zuerst in den leichtesten Teil. Die CI prüft so mehrere Teile in eigenen Jobs.)
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

SEIT=""
if [[ $# -gt 1 && "$1" == "--seit" ]]; then
  SEIT="$2"
  shift 2
fi

PACKAGES=("$@")
if [[ ${#PACKAGES[@]} -eq 0 ]]; then
  for DIR in "$ROOT"/Packages/Atlas.IDE.*/; do
    NAME="$(basename "$DIR")"
    [[ -f "$DIR$NAME.dproj" ]] && PACKAGES+=("$NAME")
  done
fi

# Packages, die die Änderungen seit $SEIT betreffen. Ändern sich nur Dateien eines Moduls (Packages/Atlas.IDE.<Modul>,
# nicht Base) und Dateien ohne Einfluss auf die Prüfung (Doku, Changelog-Fragmente, Workflows, Prüfskripte unter
# Tools/ außer Tools/Linux), genügt die Prüfung dieser Module: Module verwenden nur Base, kein anderes Modul, und Base
# verwendet kein Modul. Alles andere (Base, Common, Text, Plugin, Vcl, ToolsApi, Application, Tests, atlas.json …)
# kann jedes Package betreffen; dann bleiben alle. Was ein Modul nur über den Index anderer Packages ändert, findet der
# volle Lauf nach dem Merge auf main-merging.
betroffene_packages() {
  local -A MODULE=()
  local PFAD
  while IFS= read -r PFAD; do
    [[ -z "$PFAD" ]] && continue
    if [[ "$PFAD" =~ ^Packages/(Atlas\.IDE\.[^/]+)/ && "${BASH_REMATCH[1]}" != "Atlas.IDE.Base" ]]; then
      MODULE[${BASH_REMATCH[1]}]=1
    elif [[ "$PFAD" =~ ^(docs/|changelog\.d/|\.github/) || "$PFAD" =~ ^[^/]+\.md$ \
            || ( "$PFAD" =~ ^Tools/ && ! "$PFAD" =~ ^Tools/Linux/ ) ]]; then
      :
    else
      echo "$PFAD betrifft alle Packages" >&2
      return 1
    fi
  done < <(git -C "$ROOT" diff --name-only "$SEIT" HEAD)
  local NAME
  for NAME in "${PACKAGES[@]}"; do
    [[ -n "${MODULE[$NAME]:-}" ]] && echo "$NAME"
  done
  return 0
}

if [[ -n "$SEIT" ]]; then
  if AUSWAHL="$(betroffene_packages)"; then
    mapfile -t PACKAGES <<< "$AUSWAHL"
    [[ -z "$AUSWAHL" ]] && PACKAGES=()
    echo "Geändert seit $SEIT: nur ${#PACKAGES[@]} Modul(e) betroffen: ${PACKAGES[*]:-keins}" >&2
  fi
fi

# Teil k von n: Packages absteigend nach Zahl der .pas-Dateien, jedes in den Teil mit der kleinsten Summe.
if [[ -n "${ATLAS_SHARD:-}" ]]; then
  if [[ ! "$ATLAS_SHARD" =~ ^([0-9]+)/([0-9]+)$ ]] || (( BASH_REMATCH[1] < 1 || BASH_REMATCH[1] > BASH_REMATCH[2] )); then
    echo "ATLAS_SHARD=$ATLAS_SHARD: erwartet <k>/<n> mit 1 <= k <= n" >&2
    exit 3
  fi
  TEIL=${BASH_REMATCH[1]}
  TEILE=${BASH_REMATCH[2]}
  declare -a LAST=()
  for (( I = 1; I <= TEILE; I++ )); do LAST[I]=0; done
  AUSWAHL=()
  while read -r ZAHL NAME; do
    [[ -z "$NAME" ]] && continue
    ZIEL=1
    for (( I = 2; I <= TEILE; I++ )); do
      (( LAST[I] < LAST[ZIEL] )) && ZIEL=$I
    done
    LAST[ZIEL]=$(( LAST[ZIEL] + ZAHL ))
    (( ZIEL == TEIL )) && AUSWAHL+=("$NAME")
  done < <(for NAME in "${PACKAGES[@]}"; do
             [[ -z "$NAME" ]] && continue
             echo "$(find "$ROOT/Packages/$NAME" -name '*.pas' | wc -l) $NAME"
           done | sort -k1,1nr -k2,2)
  PACKAGES=("${AUSWAHL[@]}")
  echo "Teil $TEIL von $TEILE: ${PACKAGES[*]:-keine Packages}" >&2
fi

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
  echo "Keine Packages zu prüfen." >&2
  exit 0
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
