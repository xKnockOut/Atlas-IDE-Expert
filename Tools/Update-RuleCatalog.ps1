<#
.SYNOPSIS
    Erzeugt aus dem Regelkatalog die eingebettete Unit und die Benutzerdokumentation.

.DESCRIPTION
    Einzige Quelle ist Packages/Argus.Common/Katalog/regelkatalog.json mit den
    Übersetzungen regelkatalog.<sprache>.json (#145). Daraus entstehen:

    - Packages/Argus.Common/Source/Rules/Argus.Common.Rules.Catalog.Data.pas
    - docs/Regeln.md

    Zusätzlich wird geprüft, dass jede implementierte Regel (TRuleDescriptor.Create
    und die RuleId-Konstanten) im Katalog steht, jede Katalogregel implementiert ist
    und jede Regel Name, Beschreibung und beide Beispiele hat.

    Mit -Check wird nichts geschrieben; Exit-Code 1, wenn die erzeugten Dateien
    veraltet sind oder eine Prüfung fehlschlägt.

.EXAMPLE
    pwsh Tools/Update-RuleCatalog.ps1
    pwsh Tools/Update-RuleCatalog.ps1 -Check
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [switch] $Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CatalogDir = Join-Path $Root 'Packages/Argus.Common/Katalog'
$SourceDir = Join-Path $Root 'Packages/Argus.Common/Source'
$UnitPath = Join-Path $SourceDir 'Rules/Argus.Common.Rules.Catalog.Data.pas'
$DocPath = Join-Path $Root 'docs/Regeln.md'
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)

$Problems = New-Object System.Collections.Generic.List[string]

function Read-Text([string] $Path) {
    [System.IO.File]::ReadAllText($Path)
}

$BaseText = Read-Text (Join-Path $CatalogDir 'regelkatalog.json')
$Base = $BaseText | ConvertFrom-Json
$Overlays = [ordered]@{}
foreach ($File in Get-ChildItem $CatalogDir -Filter 'regelkatalog.*.json' | Sort-Object Name) {
    $Language = $File.Name -replace '^regelkatalog\.(.+)\.json$', '$1'
    $Overlays[$Language] = Read-Text $File.FullName
}

# Vollständigkeit der Einträge
foreach ($Rule in $Base.rules) {
    foreach ($Field in 'id', 'name', 'category', 'severity', 'description', 'bad', 'good') {
        if (-not ($Rule.PSObject.Properties.Name -contains $Field) -or [string]::IsNullOrWhiteSpace($Rule.$Field)) {
            $Problems.Add("Regel '$($Rule.id)': Feld '$Field' fehlt")
        }
    }
}

# Abgleich mit dem Quelltext
$CatalogIds = @($Base.rules | ForEach-Object { $_.id })
$Implemented = New-Object System.Collections.Generic.HashSet[string]
foreach ($File in Get-ChildItem $SourceDir -Recurse -Filter '*.pas') {
    $Text = Read-Text $File.FullName
    foreach ($Match in [regex]::Matches($Text, "TRuleDescriptor\.Create\(\s*'([^']+)'")) {
        [void]$Implemented.Add($Match.Groups[1].Value)
    }
    foreach ($Match in [regex]::Matches($Text, "\w+RuleId\s*=\s*'([^']+)'")) {
        [void]$Implemented.Add($Match.Groups[1].Value)
    }
}
foreach ($Id in $Implemented) {
    if ($CatalogIds -notcontains $Id) { $Problems.Add("Regel '$Id' ist implementiert, fehlt aber im Katalog") }
}
foreach ($Id in $CatalogIds) {
    if (-not $Implemented.Contains($Id)) { $Problems.Add("Regel '$Id' steht im Katalog, ist aber nicht implementiert") }
}
foreach ($Language in $Overlays.Keys) {
    $Overlay = $Overlays[$Language] | ConvertFrom-Json
    foreach ($Id in $CatalogIds) {
        if (-not ($Overlay.rules | Where-Object { $_.id -eq $Id })) {
            $Problems.Add("Regel '$Id' fehlt in der Übersetzung '$Language'")
        }
    }
}

# Eingebettete Unit
function ConvertTo-DelphiLiteral([string] $Text) {
    $Lines = $Text -replace "`r", '' -split "`n"
    $Parts = foreach ($Line in $Lines) {
        $Chunks = for ($I = 0; $I -lt [Math]::Max(1, $Line.Length); $I += 200) {
            "'" + ($Line.Substring($I, [Math]::Min(200, $Line.Length - $I)) -replace "'", "''") + "'"
        }
        ($Chunks -join ' + ') + ' + #10'
    }
    '    ' + ($Parts -join " +`r`n    ")
}

$Unit = New-Object System.Text.StringBuilder
[void]$Unit.Append("unit Argus.Common.Rules.Catalog.Data;`r`n`r`n")
[void]$Unit.Append("// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog*.json.`r`n")
[void]$Unit.Append("// Nicht von Hand ändern.`r`n`r`ninterface`r`n`r`n")
[void]$Unit.Append("/// <summary>Englischer Grundkatalog als JSON.</summary>`r`nfunction RuleCatalogBaseJson: string;`r`n")
[void]$Unit.Append("/// <summary>Übersetzung als JSON, '' für unbekannte Sprachen.</summary>`r`nfunction RuleCatalogOverlayJson(const ALanguage: string): string;`r`n`r`n")
[void]$Unit.Append("implementation`r`n`r`nuses`r`n  System.SysUtils;`r`n`r`n")
[void]$Unit.Append("function RuleCatalogBaseJson: string;`r`nbegin`r`n  Result :=`r`n")
[void]$Unit.Append((ConvertTo-DelphiLiteral $BaseText) + ";`r`nend;`r`n`r`n")
[void]$Unit.Append("function RuleCatalogOverlayJson(const ALanguage: string): string;`r`nbegin`r`n")
foreach ($Language in $Overlays.Keys) {
    [void]$Unit.Append("  if SameText(ALanguage, '$Language') then`r`n    Exit(`r`n")
    [void]$Unit.Append((ConvertTo-DelphiLiteral $Overlays[$Language]) + ");`r`n")
}
[void]$Unit.Append("  Result := '';`r`nend;`r`n`r`nend.`r`n")
$UnitText = $Unit.ToString()

# Benutzerdokumentation (deutsch, Beispiele aus dem Grundkatalog)
$German = if ($Overlays.Contains('de')) { $Overlays['de'] | ConvertFrom-Json } else { $null }
$CategoryNames = @{ 'bug' = 'Bug'; 'vulnerability' = 'Schwachstelle'; 'code-smell' = 'Code Smell'; 'security-hotspot' = 'Sicherheits-Hotspot' }
$SeverityNames = @{ 'error' = 'Fehler'; 'warning' = 'Warnung'; 'information' = 'Information'; 'hint' = 'Hinweis' }
$Doc = New-Object System.Text.StringBuilder
[void]$Doc.Append("# Prüfregeln`r`n`r`n")
[void]$Doc.Append("Erzeugt von ``Tools/Update-RuleCatalog.ps1`` aus dem Regelkatalog. Nicht von Hand ändern.`r`n`r`n")
[void]$Doc.Append("| Regel | Name | Kategorie | Schweregrad |`r`n|---|---|---|---|`r`n")
$Rows = foreach ($Rule in $Base.rules) {
    $Translated = if ($German) { $German.rules | Where-Object { $_.id -eq $Rule.id } | Select-Object -First 1 } else { $null }
    $Name = if ($Translated -and $Translated.PSObject.Properties.Name -contains 'name') { $Translated.name } else { $Rule.name }
    $Description = if ($Translated -and $Translated.PSObject.Properties.Name -contains 'description') { $Translated.description } else { $Rule.description }
    [pscustomobject]@{ Rule = $Rule; Name = $Name; Description = $Description }
}
foreach ($Row in $Rows) {
    [void]$Doc.Append("| [``$($Row.Rule.id)``](#$($Row.Rule.id)) | $($Row.Name) | $($CategoryNames[$Row.Rule.category]) | $($SeverityNames[$Row.Rule.severity]) |`r`n")
}
foreach ($Row in $Rows) {
    [void]$Doc.Append("`r`n<a id=""$($Row.Rule.id)""></a>`r`n## $($Row.Rule.id)`r`n`r`n")
    [void]$Doc.Append("**$($Row.Name)** · $($CategoryNames[$Row.Rule.category]) · $($SeverityNames[$Row.Rule.severity])`r`n`r`n")
    [void]$Doc.Append("$($Row.Description)`r`n`r`n")
    [void]$Doc.Append("Mit Treffer:`r`n`r`n``````pascal`r`n$($Row.Rule.bad -replace "`n", "`r`n")`r`n```````r`n`r`n")
    [void]$Doc.Append("Richtig:`r`n`r`n``````pascal`r`n$($Row.Rule.good -replace "`n", "`r`n")`r`n```````r`n")
}
$DocText = $Doc.ToString()

function Sync-File([string] $Path, [string] $Content) {
    $Current = if (Test-Path $Path) { Read-Text $Path } else { $null }
    # Zeilenenden hängen vom Checkout ab (.gitattributes, autocrlf) und zählen nicht.
    if ($null -ne $Current -and ($Current -replace "`r", '') -ceq ($Content -replace "`r", '')) { return }
    if ($Check) {
        $Problems.Add("$Path ist veraltet; pwsh Tools/Update-RuleCatalog.ps1 ausführen")
    }
    else {
        [System.IO.File]::WriteAllText($Path, $Content, $Utf8Bom)
        Write-Host "Geschrieben: $Path"
    }
}

Sync-File $UnitPath $UnitText
Sync-File $DocPath $DocText

if ($Problems.Count -gt 0) {
    $Problems | ForEach-Object { Write-Host "FEHLER: $_" }
    exit 1
}
Write-Host 'Regelkatalog in Ordnung.'
exit 0
