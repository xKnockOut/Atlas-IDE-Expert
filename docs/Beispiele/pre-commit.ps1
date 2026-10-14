# Pre-Commit-Hook für Atlas (#157): prüft nur die Units, die der
# Commit ändert, und nur die geänderten Zeilen. Bricht den Commit bei Fehlern ab.
#
# Einrichten (im Repository):
#   Copy-Item docs/Beispiele/pre-commit.ps1 .git/hooks/pre-commit.ps1
#   Set-Content .git/hooks/pre-commit "#!/bin/sh`npwsh -NoProfile -File .git/hooks/pre-commit.ps1"
#
# Den Pfad zur AtlasServer.exe bei Bedarf über ATLAS_EXE setzen.

$Exe = if ($env:ATLAS_EXE) { $env:ATLAS_EXE } else { 'AtlasServer.exe' }
$Root = (git rev-parse --show-toplevel).Trim()

# Gegen HEAD mit Index und Arbeitsverzeichnis: genau das, was gerade eingecheckt wird.
# --fail-on error (Standard): Warnungen brechen den Commit nicht ab.
& $Exe --check $Root --diff HEAD --include-uncommitted --changed-lines --min-severity error --fail-on error
if ($LASTEXITCODE -eq 1) {
    Write-Host 'Atlas meldet Fehler in geänderten Zeilen; Commit abgebrochen.'
    exit 1
}
if ($LASTEXITCODE -ne 0) {
    Write-Host "Atlas konnte nicht prüfen (Exit-Code $LASTEXITCODE); Commit abgebrochen."
    exit 1
}
exit 0
