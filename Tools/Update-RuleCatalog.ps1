<#
.SYNOPSIS
    Erzeugt aus dem Regelkatalog die eingebettete Unit und die Benutzerdokumentation.

.DESCRIPTION
    Einzige Quelle ist Packages/Atlas.Common/Katalog/regelkatalog.json mit den
    Übersetzungen regelkatalog.<sprache>.json (#145). Daraus entstehen:

    - Packages/Atlas.Common/Source/Rules/Atlas.Common.Rules.Catalog.Data.pas
    - docs/Regeln.md
    - die Regelzahlen in README.md und README_DE.md

    Zusätzlich wird geprüft, dass jede implementierte Regel (TRuleDescriptor.Create
    und die RuleId-Konstanten) im Katalog steht, jede Katalogregel implementiert ist
    und jede Regel Name, Beschreibung, beide Beispiele und eine bekannte Gruppe
    (#909) hat. Optionen (options) brauchen Name, bekannten Typ und Beschreibung.
    "safeFix" (#1352) muss ein Wahrheitswert sein; Regeln.md nennt die Regeln
    mit Sammelkorrektur.
    Regeln.md listet die Regeln nach Gruppen und je Regel ihre Optionen.

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

$CatalogDir = Join-Path $Root 'Packages/Atlas.Common/Katalog'
$SourceDir = Join-Path $Root 'Packages/Atlas.Common/Source'
$UnitPath = Join-Path $SourceDir 'Rules/Atlas.Common.Rules.Catalog.Data.pas'
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

# Gruppen der Einstellungsseite und des Fensters „Atlas-Prüfung“ (#909), Reihenfolge wie TRuleGroup.
$GroupNames = [ordered]@{
    'find-bugs' = 'Fehler finden'; 'exceptions' = 'Exceptions'; 'threads' = 'Threads'; 'database' = 'Datenbank'
    'compiler' = 'Compiler vorab'; 'robustness' = 'Robustheit und Muster'; 'performance' = 'Performance'
    'security' = 'Sicherheit'; 'components' = 'Komponenten'; 'forms' = 'Formulare und Daten'
    'architecture' = 'Architektur'; 'style' = 'Stil und Metriken'; 'packages' = 'Packages und Tests'
    'internal' = 'Atlas intern'
}
$LevelNames = @{
    'A' = 'A (Parser genügt)'
    'B' = 'B (Namensauflösung über Units)'
    'T' = 'T (braucht Ausdruckstypen; mit "group:compiler": {"typeLevel": "off"} abschaltbar)'
}
$OptionKinds = @('integer', 'boolean', 'string', 'string-list', 'number-list', 'object-list', 'json')

# Vollständigkeit der Einträge
foreach ($Rule in $Base.rules) {
    foreach ($Field in 'id', 'name', 'category', 'severity', 'group', 'description', 'bad', 'good') {
        if (-not ($Rule.PSObject.Properties.Name -contains $Field) -or [string]::IsNullOrWhiteSpace($Rule.$Field)) {
            $Problems.Add("Regel '$($Rule.id)': Feld '$Field' fehlt")
        }
    }
    if (($Rule.PSObject.Properties.Name -contains 'group') -and -not $GroupNames.Contains([string]$Rule.group)) {
        $Problems.Add("Regel '$($Rule.id)': unbekannte Gruppe '$($Rule.group)'")
    }
    if ($Rule.PSObject.Properties.Name -contains 'options') {
        foreach ($Option in @($Rule.options)) {
            foreach ($Field in 'name', 'type', 'description') {
                if (-not ($Option.PSObject.Properties.Name -contains $Field) -or [string]::IsNullOrWhiteSpace($Option.$Field)) {
                    $Problems.Add("Regel '$($Rule.id)': Option ohne '$Field'")
                }
            }
            if (($Option.PSObject.Properties.Name -contains 'type') -and ($OptionKinds -notcontains $Option.type)) {
                $Problems.Add("Regel '$($Rule.id)': Option '$($Option.name)' hat unbekannten Typ '$($Option.type)'")
            }
            # Tabelle der Seite Prüfregeln (#1133): Spalten mit Namen.
            if (($Option.PSObject.Properties.Name -contains 'type') -and ($Option.type -eq 'object-list') -and
                (-not ($Option.PSObject.Properties.Name -contains 'columns') -or @($Option.columns | Where-Object { [string]::IsNullOrWhiteSpace($_.name) }).Count -gt 0 -or @($Option.columns).Count -eq 0)) {
                $Problems.Add("Regel '$($Rule.id)': Option '$($Option.name)' braucht 'columns' mit Namen")
            }
        }
    }
    # Compilermeldungen, denen die Regel entspricht (#938), z. B. F2069.
    if ($Rule.PSObject.Properties.Name -contains 'compilerCodes') {
        foreach ($Code in @($Rule.compilerCodes)) {
            if ([string]$Code -cnotmatch '^[EFWHX]\d{4}$') {
                $Problems.Add("Regel '$($Rule.id)': ungültiger Compilercode '$Code'")
            }
        }
    }
    # Stufe der Compilerregeln (#1024): A Parser, B Namensauflösung, T Ausdruckstypen.
    if (($Rule.PSObject.Properties.Name -contains 'level') -and (@('A', 'B', 'T') -cnotcontains [string]$Rule.level)) {
        $Problems.Add("Regel '$($Rule.id)': ungültige Stufe '$($Rule.level)' (erlaubt A, B, T)")
    }
    # Sammelkorrektur (#1352): "safeFix" ist ein Wahrheitswert.
    if (($Rule.PSObject.Properties.Name -contains 'safeFix') -and -not ($Rule.safeFix -is [bool])) {
        $Problems.Add("Regel '$($Rule.id)': 'safeFix' muss true oder false sein")
    }
    # Gegenregeln (#1025): Ist eine davon an, meldet die Regel nichts.
    if ($Rule.PSObject.Properties.Name -contains 'overriddenBy') {
        foreach ($Other in @($Rule.overriddenBy)) {
            if (-not ($Base.rules | Where-Object { $_.id -eq $Other })) {
                $Problems.Add("Regel '$($Rule.id)': unbekannte Gegenregel '$Other'")
            }
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

# Eingebettete Unit. Je Katalog ein konstantes Array mit einer JSON-Zeile je Element, zur Laufzeit mit #10
# verbunden. Früher war jeder Katalog ein einziger Ausdruck aus über 5000 mit + verketteten Literalen; daran lief
# der Compiler der IDE (32 Bit) aus dem Speicher (F2046 „Zu wenig Arbeitsspeicher“).
function ConvertTo-DelphiLines([string] $Name, [string] $Text) {
    $Lines = $Text -replace "`r", '' -split "`n"
    $Parts = foreach ($Line in $Lines) {
        $Chunks = for ($I = 0; $I -lt [Math]::Max(1, $Line.Length); $I += 200) {
            "'" + ($Line.Substring($I, [Math]::Min(200, $Line.Length - $I)) -replace "'", "''") + "'"
        }
        # Jedes Stück in eine eigene Zeile: Delphi bricht bei mehr als 1023 Zeichen je Zeile ab (F2069).
        '    ' + ($Chunks -join " +`r`n    ")
    }
    "  ${Name}: array[0..$($Lines.Count - 1)] of string = (`r`n" + ($Parts -join ",`r`n") + ");`r`n"
}

$Unit = New-Object System.Text.StringBuilder
[void]$Unit.Append("unit Atlas.Common.Rules.Catalog.Data;`r`n`r`n")
[void]$Unit.Append("// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog*.json.`r`n")
[void]$Unit.Append("// Nicht von Hand ändern.`r`n// Die Beispiele ""bad"" zeigen absichtlich unsichere URLs (#1109).`r`n// lsp-ignore-file: security-insecure-http`r`n`r`ninterface`r`n`r`n")
[void]$Unit.Append("/// <summary>Englischer Grundkatalog als JSON.</summary>`r`nfunction RuleCatalogBaseJson: string;`r`n")
[void]$Unit.Append("/// <summary>Übersetzung als JSON, '' für unbekannte Sprachen.</summary>`r`nfunction RuleCatalogOverlayJson(const ALanguage: string): string;`r`n`r`n")
[void]$Unit.Append("implementation`r`n`r`nuses`r`n  System.SysUtils;`r`n`r`n")
[void]$Unit.Append("const`r`n")
[void]$Unit.Append((ConvertTo-DelphiLines 'BaseLines' $BaseText) + "`r`n")
foreach ($Language in $Overlays.Keys) {
    [void]$Unit.Append((ConvertTo-DelphiLines "OverlayLines_$Language" $Overlays[$Language]) + "`r`n")
}
[void]$Unit.Append("/// <summary>Zeilen mit #10 verbunden, auch nach der letzten.</summary>`r`nfunction Joined(const ALines: array of string): string;`r`nbegin`r`n  Result := string.Join(#10, ALines) + #10;`r`nend;`r`n`r`n")
[void]$Unit.Append("function RuleCatalogBaseJson: string;`r`nbegin`r`n  Result := Joined(BaseLines);`r`nend;`r`n`r`n")
[void]$Unit.Append("function RuleCatalogOverlayJson(const ALanguage: string): string;`r`nbegin`r`n")
foreach ($Language in $Overlays.Keys) {
    [void]$Unit.Append("  if SameText(ALanguage, '$Language') then`r`n    Exit(Joined(OverlayLines_$Language));`r`n")
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
$Rows = foreach ($Rule in $Base.rules) {
    $Translated = if ($German) { $German.rules | Where-Object { $_.id -eq $Rule.id } | Select-Object -First 1 } else { $null }
    $Name = if ($Translated -and $Translated.PSObject.Properties.Name -contains 'name') { $Translated.name } else { $Rule.name }
    $Description = if ($Translated -and $Translated.PSObject.Properties.Name -contains 'description') { $Translated.description } else { $Rule.description }
    $Options = @()
    if ($Rule.PSObject.Properties.Name -contains 'options') {
        $Options = foreach ($Option in @($Rule.options)) {
            $Text = $Option.description
            if ($Translated -and $Translated.PSObject.Properties.Name -contains 'options') {
                $Match = @($Translated.options) | Where-Object { $_.name -eq $Option.name } | Select-Object -First 1
                if ($Match) { $Text = $Match.description }
            }
            $Default = if ($Option.PSObject.Properties.Name -contains 'default') { ConvertTo-Json -InputObject $Option.default -Compress -Depth 8 } else { '' }
            [pscustomobject]@{ Name = $Option.name; Kind = $Option.type; Default = $Default; Description = $Text }
        }
    }
    [pscustomobject]@{ Rule = $Rule; Name = $Name; Description = $Description; Options = @($Options) }
}
# Gruppen (#909) in der Reihenfolge der Einstellungsseite, darin die Reihenfolge des Katalogs.
[void]$Doc.Append("## Gruppen`r`n`r`n| Gruppe | Regeln |`r`n|---|---|`r`n")
foreach ($Group in $GroupNames.Keys) {
    $InGroup = @($Rows | Where-Object { $_.Rule.group -eq $Group })
    if ($InGroup.Count -eq 0) { continue }
    [void]$Doc.Append("| [$($GroupNames[$Group])](#gruppe-$Group) | $($InGroup.Count) |`r`n")
}
foreach ($Group in $GroupNames.Keys) {
    $InGroup = @($Rows | Where-Object { $_.Rule.group -eq $Group })
    if ($InGroup.Count -eq 0) { continue }
    [void]$Doc.Append("`r`n<a id=""gruppe-$Group""></a>`r`n### $($GroupNames[$Group])`r`n`r`n")
    [void]$Doc.Append("| Regel | Name | Kategorie | Schweregrad |`r`n|---|---|---|---|`r`n")
    foreach ($Row in $InGroup) {
        [void]$Doc.Append("| [``$($Row.Rule.id)``](#$($Row.Rule.id)) | $($Row.Name) | $($CategoryNames[$Row.Rule.category]) | $($SeverityNames[$Row.Rule.severity]) |`r`n")
    }
}
[void]$Doc.Append("`r`n## Regeln`r`n")
foreach ($Row in $Rows) {
    [void]$Doc.Append("`r`n<a id=""$($Row.Rule.id)""></a>`r`n### $($Row.Rule.id)`r`n`r`n")
    [void]$Doc.Append("**$($Row.Name)** · $($CategoryNames[$Row.Rule.category]) · $($SeverityNames[$Row.Rule.severity]) · Gruppe $($GroupNames[[string]$Row.Rule.group])`r`n`r`n")
    [void]$Doc.Append("$($Row.Description)`r`n`r`n")
    if ($Row.Rule.PSObject.Properties.Name -contains 'compilerCodes') {
        [void]$Doc.Append("Entspricht der Compilermeldung $((@($Row.Rule.compilerCodes) | ForEach-Object { '`' + $_ + '`' }) -join ', ').`r`n`r`n")
    }
    if ($Row.Rule.PSObject.Properties.Name -contains 'level') {
        [void]$Doc.Append("Stufe $($LevelNames[[string]$Row.Rule.level]).`r`n`r`n")
    }
    if (($Row.Rule.PSObject.Properties.Name -contains 'safeFix') -and $Row.Rule.safeFix) {
        [void]$Doc.Append('Sammelkorrektur: Die sichere Korrektur lässt sich projektweit anwenden (`--fix ' + $Row.Rule.id + '`, MCP `fix_findings`, Befehl ' + [char]0x201E + 'Alle sicheren Treffer korrigieren ' + [char]0x2026 + [char]0x201C + ').' + "`r`n`r`n")
    }
    if ($Row.Rule.PSObject.Properties.Name -contains 'overriddenBy') {
        [void]$Doc.Append("Schweigt, solange $((@($Row.Rule.overriddenBy) | ForEach-Object { '[`' + $_ + '`](#' + $_ + ')' }) -join ' oder ') an ist.`r`n`r`n")
    }
    if ($Row.Options.Count -gt 0) {
        [void]$Doc.Append("| Option | Typ | Vorgabe | Bedeutung |`r`n|---|---|---|---|`r`n")
        foreach ($Option in $Row.Options) {
            [void]$Doc.Append("| ``$($Option.Name)`` | $($Option.Kind) | ``$($Option.Default)`` | $($Option.Description) |`r`n")
        }
        [void]$Doc.Append("`r`n")
    }
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

# Regelzahlen in README.md und README_DE.md kommen aus dem Katalog. Von Hand gepflegt liefen sie bei parallelen
# Branches auseinander, und ein Zusammenführen hinterließ Zahlenreihen wie „170 74 73 … 279“; das Muster
# \d+( \d+)* repariert auch die.
$Counts = @{ 'bug' = 0; 'code-smell' = 0; 'vulnerability' = 0; 'security-hotspot' = 0 }
foreach ($Rule in $Base.rules) {
    if (-not $Counts.ContainsKey($Rule.category)) {
        $Problems.Add("Regel $($Rule.id): unbekannte Kategorie $($Rule.category)")
        continue
    }
    $Counts[$Rule.category]++
}
$Total = @($Base.rules).Count
$Number = '\d+(?: \d+)*'
$ReadmeCounts = @(
    @{ File = 'README.md'; Patterns = @(
        @{ Find = "with $Number check rules,"; Text = "with $Total check rules," },
        @{ Find = "\| $Number check rules \("; Text = "| $Total check rules (" },
        @{ Find = "\*\*$Number check rules\*\* in four categories: $Number bugs, $Number code smells, $Number vulnerabilities, $Number security hotspots";
           Text = "**$Total check rules** in four categories: $($Counts['bug']) bugs, $($Counts['code-smell']) code smells, $($Counts['vulnerability']) vulnerabilities, $($Counts['security-hotspot']) security hotspots" }) },
    @{ File = 'README_DE.md'; Patterns = @(
        @{ Find = "mit $Number Prüfregeln,"; Text = "mit $Total Prüfregeln," },
        @{ Find = "\| $Number Prüfregeln \("; Text = "| $Total Prüfregeln (" },
        @{ Find = "\*\*$Number Prüfregeln\*\* in vier Kategorien: $Number Fehler, $Number Code-Smells, $Number Schwachstellen, $Number Sicherheits-Hotspots";
           Text = "**$Total Prüfregeln** in vier Kategorien: $($Counts['bug']) Fehler, $($Counts['code-smell']) Code-Smells, $($Counts['vulnerability']) Schwachstellen, $($Counts['security-hotspot']) Sicherheits-Hotspots" }) }
)
$Utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($Readme in $ReadmeCounts) {
    $Path = Join-Path $Root $Readme.File
    $Text = Read-Text $Path
    $New = $Text
    foreach ($Pattern in $Readme.Patterns) {
        $Found = [regex]::Matches($New, $Pattern.Find).Count
        if ($Found -ne 1) {
            $Problems.Add("$($Readme.File): Stelle für die Regelzahl ($($Pattern.Text)) $Found-mal statt einmal gefunden")
            continue
        }
        $New = [regex]::Replace($New, $Pattern.Find, { param($Match) $Pattern.Text })
    }
    if ($New -ceq $Text) { continue }
    if ($Check) {
        $Problems.Add("$($Readme.File): Regelzahlen veraltet; pwsh Tools/Update-RuleCatalog.ps1 ausführen")
    }
    else {
        [System.IO.File]::WriteAllText($Path, $New, $Utf8)
        Write-Host "Geschrieben: $Path"
    }
}

if ($Problems.Count -gt 0) {
    $Problems | ForEach-Object { Write-Host "FEHLER: $_" }
    exit 1
}
Write-Host 'Regelkatalog in Ordnung.'
exit 0
