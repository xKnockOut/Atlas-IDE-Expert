#!/usr/bin/env bash
# Übersetzt die plattformunabhängigen DUnitX-Tests aus Tools/Linux/FpcTests.txt mit Free Pascal trunk und
# führt sie aus (#1966). Netz ohne Delphi: Jeder Pull Request prüft so Atlas.Text, Atlas.Common und den
# Core-Teil des Plugins, der ohne Windows und VCL auskommt (linux-server.yml).
#
# Aufruf: Tools/Linux/Test-Fpc.sh [<Liste>]
#
#   Umgebung: ATLAS_FPC_DIR (Ort von FPC trunk, wie Build-AtlasServer.sh)
#
# Vorher muss FPC trunk bereitstehen; Tools/Linux/Build-AtlasServer.sh legt ihn an. Aufbereitet wird wie beim
# Server (Convert-ForFpc.py), nur mit dem erzeugten Testprogramm als Wurzel und den Units unter Tests/.
# Die Liste enthält nur Testunits, die unter FPC vollständig grün sind: Abweichungen der RTL von FPC (Regex,
# Codepages, Dateisystem) wären sonst Fehlalarme. Neue Testunits ohne Windows-Bezug gehören hinein.
#
# Ergebnis: Exit-Code 0, wenn alle Tests bestehen; 1 bei fehlgeschlagenen Tests, 2/3 bei Fehlern beim
# Aufbereiten bzw. Übersetzen.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIST="${1:-$REPO/Tools/Linux/FpcTests.txt}"
FPC_COMMIT="$(sed -nE 's/^FPC_COMMIT=([0-9a-f]+)$/\1/p' "$REPO/Tools/Linux/Build-AtlasServer.sh")"
FPC_DIR="${ATLAS_FPC_DIR:-$HOME/.cache/atlas-fpc/$FPC_COMMIT}"
F="$FPC_DIR/lib/fpc/3.3.1"
OUT="$REPO/Output/Linux64/FpcTests"

log() { echo "[Test-Fpc] $*" >&2; }

if [ ! -x "$F/ppcx64" ]; then
  log "FPC trunk fehlt unter $FPC_DIR; zuerst Tools/Linux/Build-AtlasServer.sh ausführen"
  exit 3
fi

rm -rf "$OUT"
mkdir -p "$OUT/Src" "$OUT/Units" "$OUT/Bin"
python3 -I "$REPO/Tools/Linux/New-FpcTestProgram.py" "$REPO" "$OUT/AtlasFpcTests.dpr" "$LIST" || exit 2
python3 -I "$REPO/Tools/Linux/Convert-ForFpc.py" "$REPO" "$OUT/Src" --root "$OUT/AtlasFpcTests.dpr" --tests >&2 || exit 2
cp "$REPO"/Tools/Linux/Compat/*.pas "$REPO"/Tools/Linux/Compat/Regex/*.pp "$REPO"/Tools/Linux/Compat/DUnitX/*.pas "$OUT/Src/"

COMMON_FLAGS=(-n -Mdelphi -Sh -dUSEWIDESTRING -O1 -g -gl -Cs8388608 -l- -vew
  -FU"$OUT/Units" -Fu"$OUT/Src" -Fu"$F/units/x86_64-linux/*" -Fi"$OUT/Src" -FE"$OUT/Bin")

# Die Regex-Units aus Compat/Regex sind unveränderte Kopien der FPC-RTL und werden wie die RTL ohne Bereichs- und
# Überlaufprüfung übersetzt (eine nicht belegte Gruppe hat dort den Versatz SIZE_MAX, +1 läuft über). Das
# folgende Übersetzen findet die fertigen .ppu und übersetzt sie nicht erneut.
log "Übersetze Regex-Units der RTL ohne Prüfungen"
for mUnit in system.regularexpressionsconsts system.regularexpressionscore system.regularexpressions; do
  if ! "$F/ppcx64" "${COMMON_FLAGS[@]}" "$OUT/Src/$mUnit.pp" >>"$OUT/build.log" 2>&1; then
    grep -E "Error|Fatal" "$OUT/build.log" | head -20 >&2
    log "Übersetzen gescheitert, Protokoll: $OUT/build.log"
    exit 3
  fi
done

log "Übersetze AtlasFpcTests"
# -Cr -Co: Bereichs- und Überlaufprüfung wie im Delphi-Debug-Build der Tests (#1980). Nur hier, nicht im Bau
# des ausgelieferten Servers (Build-AtlasServer.sh). Gewollte Überläufe (Hashes) stehen in {$Q-}-Inseln.
if ! "$F/ppcx64" "${COMMON_FLAGS[@]}" -Cr -Co \
  -o"$OUT/Bin/AtlasFpcTests" "$OUT/Src/AtlasFpcTests.pas" >>"$OUT/build.log" 2>&1; then
  grep -E "Error|Fatal" "$OUT/build.log" | head -20 >&2
  log "Übersetzen gescheitert, Protokoll: $OUT/build.log"
  exit 3
fi

log "Starte Tests"
# Die Tests lesen Daten relativ zum Repository (Tests/Data, Tests/Referenzprojekt).
cd "$REPO"
"$OUT/Bin/AtlasFpcTests" >&2
