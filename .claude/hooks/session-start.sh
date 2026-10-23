#!/usr/bin/env bash
# SessionStart-Hook für Claude-Code-Cloud-Sitzungen (#1109): baut AtlasServer für Linux und legt ihn nach
# /usr/local/bin, damit das Atlas-Plugin (MCP-Server und LSP) startet. Der Bau des Compilers läuft nur beim
# ersten Mal; danach baut das Skript nur, wenn sich der Quelltext geändert hat. Lokal tut der Hook nichts.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

"${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/Tools/Linux/Build-AtlasServer.sh" \
  --install /usr/local/bin >&2
