#!/usr/bin/env bash
# Baut AtlasServer für Linux (x86_64) mit Free Pascal trunk (#1109).
#
# Aufruf: Tools/Linux/Build-AtlasServer.sh [--install <Ordner>] [--force]
#
#   --install <Ordner>  legt das Programm zusätzlich als <Ordner>/AtlasServer ab (z. B. /usr/local/bin),
#                       dazu den Verweis <Ordner>/AtlasServer.exe: Das Claude-Code-Plugin startet unter
#                       allen Systemen den Befehl "AtlasServer.exe" (.mcp.json, .lsp.json)
#   --force             baut auch, wenn sich der Quelltext seit dem letzten Bau nicht geändert hat
#
# Ablauf:
#   1. FPC trunk im festen Stand FPC_COMMIT bauen, falls er unter ATLAS_FPC_DIR fehlt (einmalig, etwa
#      10 Minuten; als Startcompiler dient FPC 3.2.2 aus dem Paket fp-compiler). FPC 3.2.2 allein kann
#      Methodenreferenzen und anonyme Methoden nicht übersetzen.
#   2. Den Quelltext mit Convert-ForFpc.py für FPC aufbereiten (Output/Linux64/Fpc/Src).
#   3. Übersetzen nach Output/Linux64/Bin/AtlasServer.
#
# Ergebnis bei Erfolg: Exit-Code 0. Diagnose nur auf stderr; stdout bleibt frei.

set -euo pipefail

FPC_COMMIT=396d1e0be7510161af6e10db68546ede7e8e9ffa
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FPC_DIR="${ATLAS_FPC_DIR:-$HOME/.cache/atlas-fpc/$FPC_COMMIT}"
OUT="$REPO/Output/Linux64"
INSTALL=""
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --install) INSTALL="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
  esac
done

log() { echo "[Build-AtlasServer] $*" >&2; }

ppc() { echo "$FPC_DIR/lib/fpc/3.3.1/ppcx64"; }

install_fpc() {
  if [ -x "$(ppc)" ]; then
    return
  fi
  if ! command -v fpc >/dev/null 2>&1; then
    log "Startcompiler fehlt, installiere fp-compiler (FPC 3.2.2)"
    if command -v apt-get >/dev/null 2>&1; then
      (apt-get install -y fp-compiler fp-units-rtl >/dev/null 2>&1 ||
        { apt-get update >/dev/null 2>&1 && apt-get install -y fp-compiler fp-units-rtl >/dev/null 2>&1; }) ||
        { log "fp-compiler lässt sich nicht installieren"; exit 3; }
    else
      log "Kein apt-get: FPC 3.2.2 bitte selbst installieren"; exit 3
    fi
  fi
  local work
  work="$(mktemp -d)"
  log "Baue FPC trunk $FPC_COMMIT nach $FPC_DIR (einmalig, etwa 10 Minuten)"
  curl -sSLf -o "$work/fpc.tar.gz" \
    "https://gitlab.com/freepascal.org/fpc/source/-/archive/$FPC_COMMIT/source-$FPC_COMMIT.tar.gz"
  tar xzf "$work/fpc.tar.gz" -C "$work"
  (cd "$work/source-$FPC_COMMIT" &&
    make all OPT=-O1 -j"$(nproc)" >"$work/make.log" 2>&1 &&
    make install INSTALL_PREFIX="$FPC_DIR" >"$work/install.log" 2>&1) ||
    { log "FPC-Bau gescheitert, Protokoll: $work/make.log"; exit 3; }
  rm -rf "$work"
}

# Fingerabdruck aller Eingaben: Quelltext des Servers, Umwandlung, Kompatibilitäts-Units, FPC-Stand.
fingerprint() {
  {
    echo "$FPC_COMMIT"
    (cd "$REPO" && find Application Packages Tools/Linux -type f \( -name '*.pas' -o -name '*.dpr' -o -name '*.inc' \
      -o -name '*.py' -o -name '*.sh' \) -not -path '*/Tests/*' -print0 | sort -z | xargs -0 sha256sum)
  } | sha256sum | cut -d' ' -f1
}

install_fpc

STAMP="$OUT/Bin/AtlasServer.stamp"
PRINT="$(fingerprint)"
if [ "$FORCE" -eq 0 ] && [ -x "$OUT/Bin/AtlasServer" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$PRINT" ]; then
  log "AtlasServer ist aktuell"
else
  SRC="$OUT/Fpc/Src"
  UNITS="$OUT/Fpc/Units"
  rm -rf "$SRC" "$UNITS"
  mkdir -p "$SRC" "$UNITS" "$OUT/Bin"
  python3 -I "$REPO/Tools/Linux/Convert-ForFpc.py" "$REPO" "$SRC" >&2
  cp "$REPO"/Tools/Linux/Compat/*.pas "$SRC/"
  F="$FPC_DIR/lib/fpc/3.3.1"
  log "Übersetze AtlasServer"
  # -Cs: 8 MB Stapel je Thread wie {$MAXSTACKSIZE} unter Windows (#1094). -gl: Zeilennummern in Stacktraces,
  # -Xg: Debuginformationen in AtlasServer.dbg statt im Programm.
  if ! "$F/ppcx64" -n -Mdelphi -Sh -O1 -g -gl -Xg -Cs8388608 -l- -vew \
    -FU"$UNITS" -Fu"$SRC" -Fu"$F/units/x86_64-linux/*" -Fi"$SRC" -FE"$OUT/Bin" \
    -o"$OUT/Bin/AtlasServer" "$SRC/AtlasServer.pas" >"$OUT/Fpc/build.log" 2>&1; then
    grep -E "Error|Fatal" "$OUT/Fpc/build.log" | head -20 >&2
    log "Übersetzen gescheitert, Protokoll: $OUT/Fpc/build.log"
    exit 1
  fi
  echo "$PRINT" >"$STAMP"
  log "Fertig: $OUT/Bin/AtlasServer"
fi

if [ -n "$INSTALL" ]; then
  mkdir -p "$INSTALL"
  install -m 755 "$OUT/Bin/AtlasServer" "$INSTALL/AtlasServer"
  ln -sf AtlasServer "$INSTALL/AtlasServer.exe"
  log "Installiert: $INSTALL/AtlasServer"
fi
