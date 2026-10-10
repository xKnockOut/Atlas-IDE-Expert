# Pre-Commit-Hook für Argus (#157): prüft nur die Units, die der
# Commit ändert, und nur die geänderten Zeilen. Bricht den Commit bei Fehlern ab.
#
# Einrichten (im Repository):
#   Copy-Item docs/Beispiele/pre-commit.ps1 .git/hooks/pre-commit.ps1
#   Set-Content .git/hooks/pre-commit "#!/bin/sh`npwsh -NoProfile -File .git/hooks/pre-commit.ps1"
#
# Den Pfad zur ArgusServer.exe bei Bedarf über ARGUS_EXE setzen.

$Exe = if ($env:ARGUS_EXE) { $env:ARGUS_EXE } else { 'ArgusServer.exe' }
$Root = (git rev-parse --show-toplevel).Trim()

# Gegen HEAD mit Index und Arbeitsverzeichnis: genau das, was gerade eingecheckt wird.
& $Exe --check $Root --diff HEAD --include-uncommitted --changed-lines --min-severity error
if ($LASTEXITCODE -ge 2) {
    Write-Host 'Argus meldet Fehler in geänderten Zeilen; Commit abgebrochen.'
    exit 1
}
exit 0
