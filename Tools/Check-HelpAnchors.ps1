<#
.SYNOPSIS
    Prüft die Sprungziele der F1-Hilfe (#1886).

.DESCRIPTION
    F1 im Modul Hilfe springt auf Seiten der Doku mit festen Ankern. Damit
    kein F1 ins Leere führt, gilt:

    - Jedes Atlas-Dockfenster (GetIdentifier in Packages/Atlas.IDE.*/Source)
      steht in der Tabelle cWindows von Atlas.Core.Help.Links.
    - Jede Zeile von cWindows hat ihre Seite unter docs/features/de bzw.
      docs/features/en, jede außer der Optionsseite dort den Anker
      window-<kennung in Kleinbuchstaben>.
    - Jeder Schlüssel aus schemas/atlas-plugin.schema.json (außer x-state)
      hat in docs/Einstellungen.md und docs/en/Settings.md den Anker
      setting-<Schlüssel>.

    Die Anker der Regeln schreibt Update-RuleCatalog; dessen Prüfung läuft
    eigens.

    Exit-Code 0: keine Verstöße, 1: mindestens ein Verstoß.

.EXAMPLE
    pwsh Tools/Check-HelpAnchors.ps1
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Errors = [System.Collections.Generic.List[string]]::new()
$LinksUnit = Join-Path $Root 'Packages/Atlas.IDE.Help/Source/Core/Help/Atlas.Core.Help.Links.pas'
$OptionsWindow = 'AtlasOptions'

function Get-Anchors([string] $Path) {
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if (Test-Path $Path) {
        foreach ($m in [regex]::Matches((Get-Content -Raw -Encoding UTF8 $Path), '<a id="([^"]+)"')) {
            [void] $set.Add($m.Groups[1].Value)
        }
    }
    return , $set
}

# Tabelle cWindows: (Id: 'X'; German: 'Datei'; English: 'File')
$Windows = @{}
foreach ($m in [regex]::Matches((Get-Content -Raw -Encoding UTF8 $LinksUnit),
        "\(Id:\s*(?:'([^']+)'|TAtlasHelpLinks\.cOptionsWindow);\s*German:\s*'([^']+)';\s*English:\s*'([^']+)'\)")) {
    $id = $m.Groups[1].Value
    if (-not $m.Groups[1].Success) { $id = $OptionsWindow }
    $Windows[$id] = @($m.Groups[2].Value, $m.Groups[3].Value)
}
if ($Windows.Count -eq 0) {
    $Errors.Add("Tabelle cWindows in $LinksUnit nicht gefunden")
}

# Alle Dockfenster des Plugins
$Sources = Get-ChildItem -Path (Join-Path $Root 'Packages') -Directory -Filter 'Atlas.IDE.*' |
    Where-Object { Test-Path (Join-Path $_.FullName 'Source') } |
    ForEach-Object { Get-ChildItem -Path (Join-Path $_.FullName 'Source') -Recurse -Filter '*.pas' }
foreach ($file in $Sources) {
    $text = Get-Content -Raw -Encoding UTF8 $file.FullName
    foreach ($m in [regex]::Matches($text, "(?s)\.GetIdentifier:\s*string;\s*begin\s*Result\s*:=\s*'([^']+)'")) {
        $id = $m.Groups[1].Value
        if (-not $Windows.ContainsKey($id)) {
            $Errors.Add("$($file.Name): Dockfenster '$id' fehlt in cWindows (Atlas.Core.Help.Links)")
        }
    }
}

# Seiten und Anker der Fenster
foreach ($id in $Windows.Keys) {
    $anchor = 'window-' + $id.ToLowerInvariant()
    foreach ($page in @("docs/features/de/$($Windows[$id][0]).md", "docs/features/en/$($Windows[$id][1]).md")) {
        $path = Join-Path $Root $page
        if (-not (Test-Path $path)) {
            $Errors.Add("${id}: Seite $page fehlt")
        }
        elseif (($id -ne $OptionsWindow) -and -not (Get-Anchors $path).Contains($anchor)) {
            $Errors.Add("${id}: Anker $anchor fehlt in $page")
        }
    }
}

# Anker der Einstellungen
$Schema = Get-Content -Raw -Encoding UTF8 (Join-Path $Root 'schemas/atlas-plugin.schema.json') | ConvertFrom-Json -AsHashtable
$Keys = @($Schema['properties'].Values | Where-Object { $_.ContainsKey('x-key') -and -not $_.ContainsKey('x-state') } |
    ForEach-Object { $_['x-key'] })
if ($Keys.Count -eq 0) {
    $Errors.Add('Keine Schlüssel mit x-key im Schema gefunden')
}
foreach ($page in @('docs/Einstellungen.md', 'docs/en/Settings.md')) {
    $anchors = Get-Anchors (Join-Path $Root $page)
    foreach ($key in $Keys) {
        if (-not $anchors.Contains("setting-$key")) {
            $Errors.Add("Einstellung ${key}: Anker setting-$key fehlt in $page")
        }
    }
}

if ($Errors.Count -gt 0) {
    foreach ($e in $Errors) { Write-Error -ErrorAction Continue $e }
    exit 1
}
Write-Information -InformationAction Continue "Sprungziele der F1-Hilfe: $($Windows.Count) Fenster, $($Keys.Count) Einstellungen in Ordnung."
exit 0
