# Pre-Commit-Hook für die Formatierung (#1358): prüft nur die Zeilen, die der
# Commit ändert, gegen die Formatregeln des Projekts (format.* in atlas.json,
# .editorconfig) und bricht den Commit bei einer Abweichung ab.
#
# Einrichten (im Repository):
#   Copy-Item docs/Beispiele/pre-commit-formatierung.ps1 .git/hooks/pre-commit-formatierung.ps1
#   Set-Content .git/hooks/pre-commit "#!/bin/sh`npwsh -NoProfile -File .git/hooks/pre-commit-formatierung.ps1"
#
# Den Pfad zur AtlasServer.exe bei Bedarf über ATLAS_EXE setzen. Mit
# ATLAS_FORMAT_WRITE=1 formatiert der Hook die geänderten Zeilen selbst und
# nimmt die Dateien wieder in den Index auf, statt abzubrechen.

$Exe = if ($env:ATLAS_EXE) { $env:ATLAS_EXE } else { 'AtlasServer.exe' }
$Root = (git rev-parse --show-toplevel).Trim()

if ($env:ATLAS_FORMAT_WRITE -eq '1') {
    $Staged = git diff --cached --name-only --diff-filter=ACMR
    & $Exe --check $Root --format-write --changed HEAD --changed-lines --include-uncommitted
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Atlas konnte nicht formatieren (Exit-Code $LASTEXITCODE); Commit abgebrochen."
        exit 1
    }
    if ($Staged) { git add -- $Staged }
    exit 0
}

# Nur prüfen: Exit-Code 1 bei einer Abweichung, einem Syntaxfehler oder instabiler Formatierung.
& $Exe --check $Root --format-check --changed HEAD --changed-lines --include-uncommitted
if ($LASTEXITCODE -eq 1) {
    Write-Host 'Geänderte Zeilen weichen von den Formatregeln ab; Commit abgebrochen.'
    Write-Host 'Beheben mit: AtlasServer.exe --check . --format-write --changed HEAD --changed-lines --include-uncommitted'
    exit 1
}
if ($LASTEXITCODE -ne 0) {
    Write-Host "Atlas konnte nicht prüfen (Exit-Code $LASTEXITCODE); Commit abgebrochen."
    exit 1
}
exit 0
