<#
.SYNOPSIS
    Erzeugt docs/Konfiguration.md aus dem JSON-Schema von delphi-lsp.json.

.DESCRIPTION
    Einzige Quelle ist Editors/VSCode/schemas/delphi-lsp.schema.json. Jeder
    Schlüssel bekommt eine Zeile mit Typ, Standardwert, erlaubten Werten und
    Beschreibung; verschachtelte Objekte erscheinen als eigener Abschnitt.

    Mit -Check wird nichts geschrieben; Exit-Code 1, wenn die Datei veraltet ist.

.EXAMPLE
    pwsh Tools/Update-ConfigDoc.ps1
    pwsh Tools/Update-ConfigDoc.ps1 -Check
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [switch] $Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SchemaPath = Join-Path $Root 'Editors/VSCode/schemas/delphi-lsp.schema.json'
$DocPath = Join-Path $Root 'docs/Konfiguration.md'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

$Schema = Get-Content -Raw -Encoding utf8 $SchemaPath | ConvertFrom-Json -AsHashtable

function Has([hashtable] $Node, [string] $Key) { $Node.ContainsKey($Key) -and $null -ne $Node[$Key] }

function Format-Value($Value) {
    if ($Value -is [bool]) { return '`' + $Value.ToString().ToLowerInvariant() + '`' }
    if ($Value -is [string]) { return '`"' + $Value + '"`' }
    return '`' + ($Value | ConvertTo-Json -Compress) + '`'
}

function Escape([string] $Text) { $Text.Replace('|', '\|').Replace("`r", '').Replace("`n", ' ') }

function Write-Table([System.Text.StringBuilder] $Out, [hashtable] $Properties, [string] $Prefix) {
    [void]$Out.AppendLine('| Schlüssel | Typ | Standard | Werte | Bedeutung |')
    [void]$Out.AppendLine('|---|---|---|---|---|')
    foreach ($Name in $Properties.Keys) {
        if ($Name -eq '$schema') { continue }
        $P = $Properties[$Name]
        $Type = if (Has $P 'type') { $P['type'] } else { '' }
        if ($Type -eq 'array' -and (Has $P 'items') -and (Has $P['items'] 'type')) { $Type = "array<$($P['items']['type'])>" }
        $Default = if ($P.ContainsKey('default')) { Format-Value $P['default'] } else { '–' }
        $Values = if (Has $P 'enum') { ($P['enum'] | ForEach-Object { Format-Value $_ }) -join ', ' }
                  elseif (Has $P 'examples') { 'z. B. ' + (($P['examples'] | ForEach-Object { Format-Value $_ }) -join ', ') }
                  elseif ((Has $P 'minimum') -or (Has $P 'maximum')) { "$(if (Has $P 'minimum') { $P['minimum'] } else { '' })…$(if (Has $P 'maximum') { $P['maximum'] } else { '' })" }
                  else { '' }
        $Description = if (Has $P 'description') { Escape $P['description'] } else { '' }
        [void]$Out.AppendLine("| ``$Prefix$Name`` | $Type | $Default | $Values | $Description |")
    }
}

$Out = New-Object System.Text.StringBuilder
[void]$Out.AppendLine('# Konfiguration: delphi-lsp.json')
[void]$Out.AppendLine()
[void]$Out.AppendLine('<!-- Erzeugt von Tools/Update-ConfigDoc.ps1 aus Editors/VSCode/schemas/delphi-lsp.schema.json. Nicht von Hand bearbeiten. -->')
[void]$Out.AppendLine()
[void]$Out.AppendLine((Escape $Schema['description']))
[void]$Out.AppendLine()
[void]$Out.AppendLine('Die Datei liegt im Projektordner. Fehlende Schlüssel nehmen den Standardwert; Editor-Einstellungen gelten nur, wo die Datei nichts sagt. Die Prüfregeln stehen in [Regeln.md](Regeln.md).')
[void]$Out.AppendLine()
[void]$Out.AppendLine('## Schlüssel')
[void]$Out.AppendLine()
Write-Table $Out $Schema['properties'] ''
foreach ($Name in $Schema['properties'].Keys) {
    $P = $Schema['properties'][$Name]
    if ((Has $P 'properties')) {
        [void]$Out.AppendLine()
        [void]$Out.AppendLine("## $Name")
        [void]$Out.AppendLine()
        Write-Table $Out $P['properties'] "$Name."
    }
}
[void]$Out.AppendLine()
[void]$Out.AppendLine('## Beispiel')
[void]$Out.AppendLine()
[void]$Out.AppendLine('```json')
[void]$Out.AppendLine('{')
[void]$Out.AppendLine('  "$schema": "https://raw.githubusercontent.com/xKnockOut/BetterDelphiLSP/main/Editors/VSCode/schemas/delphi-lsp.schema.json",')
[void]$Out.AppendLine('  "project": "App.dproj",')
[void]$Out.AppendLine('  "config": "Debug",')
[void]$Out.AppendLine('  "platform": "Win64",')
[void]$Out.AppendLine('  "rules": { "empty-except": "error" },')
[void]$Out.AppendLine('  "exclude": ["ThirdParty/**"]')
[void]$Out.AppendLine('}')
[void]$Out.AppendLine('```')
$Text = $Out.ToString().Replace("`r`n", "`n")

$Current = if (Test-Path $DocPath) { [IO.File]::ReadAllText($DocPath, $Utf8).Replace("`r`n", "`n") } else { '' }
if ($Check) {
    if ($Current -ne $Text) {
        Write-Error 'docs/Konfiguration.md ist veraltet: pwsh Tools/Update-ConfigDoc.ps1 ausführen.' -ErrorAction Continue
        exit 1
    }
    Write-Host 'docs/Konfiguration.md ist aktuell.'
    exit 0
}
[IO.File]::WriteAllText($DocPath, $Text, $Utf8)
Write-Host "Geschrieben: $DocPath"
