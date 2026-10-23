#!/usr/bin/env bash
# Baut AtlasServer für Linux (x86_64) mit Free Pascal trunk (#1109).
#
# Aufruf: Tools/Linux/Build-AtlasServer.sh [--install <Ordner>] [--force] [--no-download]
#                                           [--package <Ordner>] [--fingerprint]
#
#   Umgebung: ATLAS_FPC_DIR (Ort von FPC trunk), ATLAS_GITHUB_REPO (owner/repo des Releases, sonst aus origin),
#   ATLAS_ASSET_DIR (Release-Dateien aus diesem Ordner statt von GitHub)
#
#   --install <Ordner>  legt das Programm zusätzlich als <Ordner>/AtlasServer ab (z. B. /usr/local/bin),
#                       dazu den Verweis <Ordner>/AtlasServer.exe: Das Claude-Code-Plugin startet unter
#                       allen Systemen den Befehl "AtlasServer.exe" (.mcp.json, .lsp.json)
#   --force             baut auch, wenn sich der Quelltext seit dem letzten Bau nicht geändert hat
#   --no-download       lädt nichts aus dem Release "cloud-linux", sondern baut immer selbst (CI)
#   --package <Ordner>  legt nach dem Bau die beiden Release-Dateien in <Ordner> ab (CI, siehe unten)
#   --fingerprint       gibt nur den Fingerabdruck des Quelltexts auf stdout aus
#
# Ablauf:
#   1. Fingerabdruck aller Eingaben bilden. Passt ein schon gebautes Programm dazu, ist nichts zu tun.
#   2. Fertiges Programm aus dem GitHub-Release "cloud-linux" laden (AtlasServer-x86_64-linux.tar.xz, baut
#      der Workflow linux-server.yml bei jedem Push auf main). Es gilt nur, wenn sein Fingerabdruck zum
#      Quelltext passt, also auf main und auf Branches ohne Änderungen am Server. Dauert Sekunden.
#   3. Sonst FPC trunk im festen Stand FPC_COMMIT bereitstellen, falls er unter ATLAS_FPC_DIR fehlt: erst
#      fertig gebaut aus demselben Release laden (fpc-<FPC_COMMIT>-x86_64-linux.tar.xz), sonst selbst bauen
#      (etwa 10 Minuten; als Startcompiler dient FPC 3.2.2 aus dem Paket fp-compiler). FPC 3.2.2 allein kann
#      Methodenreferenzen und anonyme Methoden nicht übersetzen.
#   4. Den Quelltext mit Convert-ForFpc.py für FPC aufbereiten (Output/Linux64/Fpc/Src).
#   5. Übersetzen nach Output/Linux64/Bin/AtlasServer (etwa 2 Minuten).
#
# Warum vorgefertigt: Claude Code startet den MCP-Server des Plugins beim Start der Sitzung und versucht es
# danach nicht erneut. Ein Bau von 12 Minuten in der Sitzung kommt dafür zu spät, und ein Setup-Skript der
# Cloud-Umgebung wird nur zwischengespeichert, wenn es in etwa 5 Minuten fertig ist (ADR 0013).
#
# Zwei Aufrufe gleichzeitig (Setup-Skript und SessionStart-Hook) warten aufeinander (flock).
#
# Ergebnis bei Erfolg: Exit-Code 0. Diagnose nur auf stderr; stdout bleibt frei.

set -euo pipefail

FPC_COMMIT=396d1e0be7510161af6e10db68546ede7e8e9ffa
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FPC_DIR="${ATLAS_FPC_DIR:-$HOME/.cache/atlas-fpc/$FPC_COMMIT}"
OUT="$REPO/Output/Linux64"
INSTALL=""
FORCE=0
DOWNLOAD=1
PACKAGE=""
ONLY_PRINT=0
RELEASE_TAG=cloud-linux
SERVER_ASSET=AtlasServer-x86_64-linux.tar.xz
FPC_ASSET="fpc-$FPC_COMMIT-x86_64-linux.tar.xz"

while [ $# -gt 0 ]; do
  case "$1" in
    --install) INSTALL="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --no-download) DOWNLOAD=0; shift ;;
    --package) PACKAGE="$2"; shift 2 ;;
    --fingerprint) ONLY_PRINT=1; shift ;;
    *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
  esac
done

log() { echo "[Build-AtlasServer] $*" >&2; }

ppc() { echo "$FPC_DIR/lib/fpc/3.3.1/ppcx64"; }

# owner/repo für die Release-Dateien: ATLAS_GITHUB_REPO, sonst aus der Adresse von origin.
github_repo() {
  if [ -n "${ATLAS_GITHUB_REPO:-}" ]; then
    echo "$ATLAS_GITHUB_REPO"
    return
  fi
  git -C "$REPO" remote get-url origin 2>/dev/null |
    sed -nE 's#^.*github\.com[:/]+([^/]+/[^/]+)$#\1#p' | sed 's#\.git$##' | head -1
}

# Lädt die Datei $1 des Releases RELEASE_TAG nach $2. In Cloud-Sitzungen meldet der Proxy die Sitzung bei
# GitHub an; in der CI und lokal gilt GH_TOKEN bzw. GITHUB_TOKEN, falls gesetzt.
fetch_asset() {
  local name="$1" target="$2" repo auth=() id
  [ "$DOWNLOAD" -eq 1 ] || return 1
  # ATLAS_ASSET_DIR: Release-Dateien aus einem Ordner statt von GitHub (Test, Rechner ohne Netz).
  if [ -n "${ATLAS_ASSET_DIR:-}" ]; then
    [ -f "$ATLAS_ASSET_DIR/$name" ] && cp "$ATLAS_ASSET_DIR/$name" "$target"
    return
  fi
  command -v curl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || return 1
  repo="$(github_repo)"
  [ -n "$repo" ] || return 1
  if [ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
    auth=(-H "Authorization: Bearer ${GH_TOKEN:-${GITHUB_TOKEN:-}}")
  fi
  id="$(curl -sSLf "${auth[@]}" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$repo/releases/tags/$RELEASE_TAG" 2>/dev/null |
    python3 -I -c 'import json, sys
name = sys.argv[1]
for asset in json.load(sys.stdin).get("assets", []):
    if asset.get("name") == name:
        print(asset["id"])
        break' "$name" 2>/dev/null)" || return 1
  [ -n "$id" ] || return 1
  log "Lade $name aus dem Release $RELEASE_TAG von $repo"
  curl -sSLf "${auth[@]}" -H "Accept: application/octet-stream" \
    "https://api.github.com/repos/$repo/releases/assets/$id" -o "$target" 2>/dev/null
}

# Fertig gebautes Programm passend zum Fingerabdruck $1 nach $OUT/Bin legen.
fetch_server() {
  local work
  work="$(mktemp -d)"
  if fetch_asset "$SERVER_ASSET" "$work/server.tar.xz" && tar xJf "$work/server.tar.xz" -C "$work" 2>/dev/null &&
    [ -x "$work/AtlasServer" ] && [ "$(cat "$work/AtlasServer.stamp" 2>/dev/null)" = "$1" ]; then
    mkdir -p "$OUT/Bin"
    install -m 755 "$work/AtlasServer" "$OUT/Bin/AtlasServer"
    echo "$1" >"$OUT/Bin/AtlasServer.stamp"
    rm -rf "$work"
    return 0
  fi
  rm -rf "$work"
  return 1
}

install_fpc() {
  if [ -x "$(ppc)" ]; then
    return
  fi
  local fetched
  fetched="$(mktemp -d)"
  if fetch_asset "$FPC_ASSET" "$fetched/fpc.tar.xz"; then
    mkdir -p "$FPC_DIR"
    if tar xJf "$fetched/fpc.tar.xz" -C "$FPC_DIR" 2>/dev/null && [ -x "$(ppc)" ]; then
      rm -rf "$fetched"
      log "FPC trunk $FPC_COMMIT aus dem Release übernommen"
      return
    fi
    log "FPC-Archiv aus dem Release unbrauchbar, baue selbst"
  fi
  rm -rf "$fetched"
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
      -o -name '*.py' -o -name '*.sh' \) -not -path '*/Tests/*' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum)
  } | sha256sum | cut -d' ' -f1
}

PRINT="$(fingerprint)"
if [ "$ONLY_PRINT" -eq 1 ]; then
  echo "$PRINT"
  exit 0
fi

mkdir -p "$OUT"
exec 9>"$OUT/.build.lock"
flock 9

STAMP="$OUT/Bin/AtlasServer.stamp"
if [ "$FORCE" -eq 0 ] && [ -x "$OUT/Bin/AtlasServer" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$PRINT" ]; then
  log "AtlasServer ist aktuell"
elif [ "$FORCE" -eq 0 ] && fetch_server "$PRINT"; then
  log "AtlasServer aus dem Release übernommen (passt zum Quelltext)"
else
  install_fpc
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

if [ -n "$PACKAGE" ]; then
  # Release-Dateien für linux-server.yml: Programm mit Fingerabdruck und der gebaute FPC trunk.
  mkdir -p "$PACKAGE"
  PACKAGE="$(cd "$PACKAGE" && pwd)"
  export XZ_OPT="${XZ_OPT:--T0}"
  tar cJf "$PACKAGE/$SERVER_ASSET" -C "$OUT/Bin" AtlasServer AtlasServer.stamp
  if [ -x "$(ppc)" ]; then
    tar cJf "$PACKAGE/$FPC_ASSET" -C "$FPC_DIR" .
  fi
  log "Release-Dateien in $PACKAGE"
fi

if [ -n "$INSTALL" ]; then
  mkdir -p "$INSTALL"
  install -m 755 "$OUT/Bin/AtlasServer" "$INSTALL/AtlasServer"
  ln -sf AtlasServer "$INSTALL/AtlasServer.exe"
  log "Installiert: $INSTALL/AtlasServer"
fi
