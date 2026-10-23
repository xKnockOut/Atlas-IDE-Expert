#!/usr/bin/env bash
# PostToolUse-Hook nach Edit/Write (CLAUDE.md): hält die Dateiregeln dieses Repositorys ein, bevor ein Fehler erst
# beim Delphi-Bau auffällt.
#
# - .pas/.dpr/.dpk/.inc/.dfm/.dproj/.groupproj/.ps1: Zeilenenden CRLF. Das Write-Werkzeug schreibt LF; der Hook
#   wandelt um, statt Claude eine Meldung zurückzuschicken.
# - .pas/.dpr/.dpk/.inc/.ps1: UTF-8 mit BOM; der Hook ergänzt ein fehlendes BOM.
# - .pas/.dpr/.dpk/.inc/.dproj: Tools/Check-Delphi12.ps1 für diese Datei, wenn pwsh vorhanden ist. Ein Verstoß geht
#   mit Exit-Code 2 an Claude zurück. Ohne pwsh erfährt Claude einmal je Sitzung, was ungeprüft bleibt.
#
# Die Befunde der Prüfregeln liefert der Hook des Plugins atlas (MCP-Werkzeug hook_check).
# Braucht nur bash, sed und perl (unter Windows aus Git for Windows).
set -uo pipefail

input="$(cat)"
file="$(printf '%s' "$input" | sed -nE 's/.*"file_path"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -1)"
file="${file//\\\\/\\}"
[ -n "$file" ] && [ -f "$file" ] || exit 0

ext="${file##*.}"
ext="${ext,,}"
changed=()

case "$ext" in
  pas|dpr|dpk|inc|dfm|dproj|groupproj|ps1)
    if perl -ne 'exit 1 if /(?<!\r)\n/' "$file"; then :; else
      perl -i -pe 's/\r?\n/\r\n/' "$file"
      changed+=("Zeilenenden auf CRLF umgestellt")
    fi
    ;;
esac

case "$ext" in
  pas|dpr|dpk|inc|ps1)
    if [ "$(head -c 3 "$file" | od -An -tx1 | tr -d ' \n')" != "efbbbf" ]; then
      perl -i -pe 'print "\xEF\xBB\xBF" if $. == 1' "$file"
      changed+=("BOM ergänzt")
    fi
    ;;
esac

if [ ${#changed[@]} -gt 0 ]; then
  summary="${changed[0]}"
  for item in "${changed[@]:1}"; do summary="$summary, $item"; done
  echo "nach-bearbeitung: $file: $summary" >&2
fi

case "$ext" in
  pas|dpr|dpk|inc|dproj)
    if command -v pwsh >/dev/null 2>&1; then
      root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
      if ! report="$(pwsh -NoProfile -File "$root/Tools/Check-Delphi12.ps1" -Root "$root" -Files "$file" 2>&1)"; then
        echo "$report" >&2
        echo "Delphi 12 muss diesen Quelltext übersetzen (CLAUDE.md): Stelle umschreiben." >&2
        exit 2
      fi
    else
      # Ohne pwsh (Cloud-Sitzung) nicht still überspringen (#1126): Claude einmal je Sitzung sagen, was dann
      # ungeprüft bleibt. Die Sprachmerkmale von Delphi 13 meldet weiter der Plugin-Hook (Regel language-feature,
      # minDelphiVersion in atlas.json).
      session="$(printf '%s' "$input" | sed -nE 's/.*"session_id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -1)"
      marker="${TMPDIR:-/tmp}/atlas-check-delphi12-${session:-ohne-sitzung}"
      if [ ! -e "$marker" ]; then
        : > "$marker"
        printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Tools/Check-Delphi12.ps1 lief nicht, weil pwsh fehlt. Ungeprüft bleiben GetWindowLong/SetWindowLong statt …LongPtr, Zeiger-Integer-Umwandlungen und die ProjectVersion der .dproj; darauf beim Schreiben selbst achten. Die Sprachmerkmale von Delphi 13 (If-Ausdruck, is not, not in) prüft Atlas über hook_check."}}'
      fi
    fi
    ;;
esac
exit 0
