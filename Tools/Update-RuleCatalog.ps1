<#
.SYNOPSIS
    Erzeugt aus dem Regelkatalog die eingebettete Unit und die Benutzerdokumentation.

.DESCRIPTION
    Einzige Quelle ist Packages/Atlas.Common/Katalog/regelkatalog.json mit den
    Übersetzungen regelkatalog.<sprache>.json (#145). Daraus entstehen:

    - Packages/Atlas.Common/Source/Rules/Atlas.Common.Rules.Catalog.Data.pas und die Teil-Units
      Atlas.Common.Rules.Catalog.Data.<Sprache>.<Gruppe>.pas (je Regelgruppe, compiler je Stufe)
    - docs/Regeln.md und docs/en/Rules.md (#1458)
    - die Regelzahlen in README.md, README_DE.md und den Seiten Code-Analyse (docs/features)

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
$DocPathEn = Join-Path $Root 'docs/en/Rules.md'
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

# Eingebettete Units. Je Katalog konstante Arrays mit einer JSON-Zeile je Element, zur Laufzeit mit #10 verbunden.
# Früher war jeder Katalog ein einziger Ausdruck aus über 5000 mit + verketteten Literalen; daran lief der Compiler
# der IDE (32 Bit) aus dem Speicher (F2046 „Zu wenig Arbeitsspeicher“). Die Regeln stehen deshalb in Teil-Units je
# Gruppe der Einstellungsseite (#909), Atlas.Common.Rules.Catalog.Data.<Sprache>.<Gruppe>, die Gruppe compiler
# zusätzlich nach Stufe geteilt (CompilerSyntax, CompilerNames, CompilerTypes). So bleibt jede Unit unter der Grenze
# von metric-unit-length (2000), und der Name sagt, welche Regeln sie enthält. Atlas.Common.Rules.Catalog.Data fügt
# über Atlas.Common.Rules.Catalog.Data.<Sprache> die Teile in der Reihenfolge der Gruppen zusammen; innerhalb einer Gruppe gilt die Reihenfolge des Katalogs.
$PartLimit = 1900
$PartPrefix = 'Atlas.Common.Rules.Catalog.Data.'
$CompilerLevelParts = [ordered]@{ 'A' = 'CompilerSyntax'; 'B' = 'CompilerNames'; 'T' = 'CompilerTypes' }

function ConvertTo-DelphiLine([string] $Line) {
    $Chunks = for ($I = 0; $I -lt [Math]::Max(1, $Line.Length); $I += 200) {
        "'" + ($Line.Substring($I, [Math]::Min(200, $Line.Length - $I)) -replace "'", "''") + "'"
    }
    # Jedes Stück in eine eigene Zeile: Delphi bricht bei mehr als 1023 Zeichen je Zeile ab (F2069).
    '    ' + (@($Chunks) -join " +`r`n    ")
}

# Texte der Elemente von "rules" in $Text, unverändert aus der Datei, in der Reihenfolge des Katalogs.
function Get-RuleTexts([string] $Text, [string] $Source) {
    $Texts = New-Object System.Collections.Generic.List[string]
    $Depth = 0
    $InString = $false
    $Escaped = $false
    $Start = -1
    for ($I = 0; $I -lt $Text.Length; $I++) {
        $Char = $Text[$I]
        if ($InString) {
            if ($Escaped) { $Escaped = $false }
            elseif ($Char -eq '\') { $Escaped = $true }
            elseif ($Char -eq '"') { $InString = $false }
            continue
        }
        if ($Char -eq '"') { $InString = $true; continue }
        if ($Char -eq '{' -or $Char -eq '[') {
            $Depth++
            if ($Depth -eq 3 -and $Char -eq '{') { $Start = $I }
        }
        elseif ($Char -eq '}' -or $Char -eq ']') {
            if ($Depth -eq 3 -and $Char -eq '}') { $Texts.Add($Text.Substring($Start, $I - $Start + 1)) }
            $Depth--
        }
    }
    $Parsed = $Text | ConvertFrom-Json
    if ((@($Parsed.PSObject.Properties.Name) -join ',') -ne 'rules' -or $Texts.Count -ne @($Parsed.rules).Count) {
        $Problems.Add("Katalog\${Source}: erwartet ein Objekt nur mit ""rules"" und je Regel ein Objekt")
    }
    , $Texts
}

# Name des Teils einer Regel: die Gruppe in Pascal-Schreibweise (find-bugs -> FindBugs), compiler nach Stufe.
function Get-PartName($Rule) {
    if ($Rule.group -eq 'compiler') {
        return $CompilerLevelParts[[string]$Rule.level]
    }
    (@(([string]$Rule.group) -split '-') | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join ''
}

# Reihenfolge der Teile: Gruppen wie auf der Einstellungsseite, compiler als seine drei Stufen.
$PartOrder = foreach ($Group in $GroupNames.Keys) {
    if ($Group -eq 'compiler') { $CompilerLevelParts.Values }
    else { Get-PartName ([pscustomobject]@{ group = $Group }) }
}
$PartOfRule = @{}
foreach ($Rule in $Base.rules) {
    $PartOfRule[[string]$Rule.id] = Get-PartName $Rule
}

function New-PartUnit([string] $Name, [string] $Const, [string] $Source, $Lines) {
    $Header = "// Nicht von Hand ändern.`r`n"
    # Nur Teile mit einer echten http://-Adresse (Beispiel "bad" der Regel) unterdrücken die Regel, sonst meldet
    # unused-suppression die wirkungslose Unterdrückung.
    if (@($Lines | Where-Object { $_ -match 'http://(?!localhost|127\.|\[::1\])\w' }).Count -gt 0) {
        $Header += "// Die Beispiele ""bad"" zeigen absichtlich unsichere URLs (#1109).`r`n// lsp-ignore-file: security-insecure-http`r`n"
    }
    $Pascal = @($Lines | ForEach-Object { ConvertTo-DelphiLine $_ })
    "unit $Name;`r`n`r`n// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\$Source.`r`n" + $Header +
    "`r`ninterface`r`n`r`nconst`r`n" +
    "  ${Const}: array[0..$($Pascal.Count - 1)] of string = (`r`n" + ($Pascal -join ",`r`n") + ");`r`n`r`n" +
    "implementation`r`n`r`nend.`r`n"
}

# Kürzel der Kataloge: En für den Grundkatalog, sonst die Sprache mit großem Anfangsbuchstaben (De).
$Catalogs = [ordered]@{ 'En' = @{ Source = 'regelkatalog.json'; Text = $BaseText } }
foreach ($Language in $Overlays.Keys) {
    $Key = $Language.Substring(0, 1).ToUpperInvariant() + $Language.Substring(1)
    $Catalogs[$Key] = @{ Source = "regelkatalog.$Language.json"; Text = $Overlays[$Language] }
}
$PartUnits = [ordered]@{}
$PartConsts = @{}
$PartUnitOfConst = @{}
foreach ($Key in $Catalogs.Keys) {
    $Source = $Catalogs[$Key].Source
    $Grouped = @{}
    foreach ($RuleText in (Get-RuleTexts $Catalogs[$Key].Text $Source)) {
        $Id = [string](($RuleText | ConvertFrom-Json).id)
        if (-not $PartOfRule.ContainsKey($Id)) {
            $Problems.Add("Katalog\${Source}: Regel '$Id' fehlt im Grundkatalog")
            continue
        }
        $Part = $PartOfRule[$Id]
        if (-not $Grouped.ContainsKey($Part)) { $Grouped[$Part] = New-Object System.Collections.Generic.List[string] }
        $Grouped[$Part].Add($RuleText)
    }
    $Consts = @()
    foreach ($Part in $PartOrder) {
        if (-not $Grouped.ContainsKey($Part)) { continue }
        # Regeln eines Teils mit Komma getrennt; die Kommas zwischen den Teilen setzt Catalog.Data.
        $Lines = @(($Grouped[$Part] -join ",`n") -replace "`r", '' -split "`n")
        $Name = "$PartPrefix$Key.$Part"
        $Const = "cCatalogLines$Key$Part"
        $PartUnits[$Name] = New-PartUnit $Name $Const $Source $Lines
        $PartUnitOfConst[$Const] = $Name
        $Size = @($PartUnits[$Name] -split "`n").Count
        if ($Size -gt $PartLimit) {
            $Problems.Add("$Name hat $Size Zeilen (höchstens $PartLimit): die Gruppe in Get-PartName weiter nach Inhalt teilen")
        }
        $Consts += $Const
    }
    $PartConsts[$Key] = $Consts
}

# Je Sprache eine Unit Atlas.Common.Rules.Catalog.Data.<Sprache>, die ihre Teile zum JSON zusammenfügt; so bindet
# keine Unit mehr als 30 Units ein (metric-uses-count).
function New-LanguageUnit([string] $Key, [string] $Source) {
    $Name = "$PartPrefix$Key"
    $Text = New-Object System.Text.StringBuilder
    [void]$Text.Append("unit $Name;`r`n`r`n// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\$Source.`r`n")
    [void]$Text.Append("// Nicht von Hand ändern. Die Regeln stehen je Gruppe in den Teil-Units $Name.<Gruppe>.`r`n`r`ninterface`r`n`r`n")
    [void]$Text.Append("/// <summary>Der Katalog aus $Source als JSON, Regeln nach Gruppen geordnet.</summary>`r`n")
    [void]$Text.Append("function RuleCatalog${Key}Json: string;`r`n`r`nimplementation`r`n`r`nuses`r`n  System.SysUtils,`r`n  ")
    [void]$Text.Append((@($PartConsts[$Key]) | ForEach-Object { $PartUnitOfConst[$_] }) -join ",`r`n  ")
    [void]$Text.Append(";`r`n`r`n/// <summary>Zeilen mit #10 verbunden, auch nach der letzten.</summary>`r`nfunction Joined(const ALines: array of string): string;`r`nbegin`r`n  Result := string.Join(#10, ALines) + #10;`r`nend;`r`n`r`n")
    [void]$Text.Append("function RuleCatalog${Key}Json: string;`r`nbegin`r`n  Result := '{' + #10 + '  ""rules"": [' + #10 +`r`n    ")
    [void]$Text.Append((@($PartConsts[$Key]) | ForEach-Object { "Joined($_)" }) -join " + ',' + #10 +`r`n    ")
    [void]$Text.Append(" +`r`n    '  ]' + #10 + '}' + #10;`r`nend;`r`n`r`nend.`r`n")
    $Text.ToString()
}
$LanguageUnits = [ordered]@{}
foreach ($Key in $Catalogs.Keys) {
    $LanguageUnits["$PartPrefix$Key"] = New-LanguageUnit $Key $Catalogs[$Key].Source
}

$Unit = New-Object System.Text.StringBuilder
[void]$Unit.Append("unit Atlas.Common.Rules.Catalog.Data;`r`n`r`n")
[void]$Unit.Append("// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog*.json.`r`n")
[void]$Unit.Append("// Nicht von Hand ändern. Je Sprache eine Unit $PartPrefix<Sprache>,`r`n// die Regeln je Gruppe in deren Teil-Units.`r`n`r`ninterface`r`n`r`n")
[void]$Unit.Append("/// <summary>Englischer Grundkatalog als JSON.</summary>`r`nfunction RuleCatalogBaseJson: string;`r`n")
[void]$Unit.Append("/// <summary>Übersetzung als JSON, '' für unbekannte Sprachen.</summary>`r`nfunction RuleCatalogOverlayJson(const ALanguage: string): string;`r`n`r`n")
[void]$Unit.Append("implementation`r`n`r`nuses`r`n  System.SysUtils")
foreach ($Name in $LanguageUnits.Keys) {
    [void]$Unit.Append(",`r`n  $Name")
}
[void]$Unit.Append(";`r`n`r`n")
[void]$Unit.Append("function RuleCatalogBaseJson: string;`r`nbegin`r`n  Result := RuleCatalogEnJson;`r`nend;`r`n`r`n")
[void]$Unit.Append("function RuleCatalogOverlayJson(const ALanguage: string): string;`r`nbegin`r`n")
foreach ($Language in $Overlays.Keys) {
    $Key = $Language.Substring(0, 1).ToUpperInvariant() + $Language.Substring(1)
    [void]$Unit.Append("  if SameText(ALanguage, '$Language') then`r`n  begin`r`n    Exit(RuleCatalog${Key}Json);`r`n  end;`r`n")
}
[void]$Unit.Append("  Result := '';`r`nend;`r`n`r`nend.`r`n")
foreach ($Name in $LanguageUnits.Keys) {
    $PartUnits[$Name] = $LanguageUnits[$Name]
}
$UnitText = $Unit.ToString()

# Benutzerdokumentation: docs/Regeln.md (deutsch, Übersetzung aus regelkatalog.de.json) und docs/en/Rules.md
# (englisch, Grundkatalog), beide mit den Beispielen des Grundkatalogs (#1458).
$DocTexts = @{
    'de' = @{
        Title = 'Prüfregeln'; Generated = 'Erzeugt von ``Tools/Update-RuleCatalog.ps1`` aus dem Regelkatalog. Nicht von Hand ändern.'
        Other = '*English version: [en/Rules.md](en/Rules.md)*'
        Groups = 'Gruppen'; Group = 'Gruppe'; RulesHead = 'Regeln'; RuleCol = 'Regel'; NameCol = 'Name'; CategoryCol = 'Kategorie'; SeverityCol = 'Schweregrad'
        Anchor = 'gruppe'; InGroup = 'Gruppe'; Compiler = 'Entspricht der Compilermeldung {0}.'; Level = 'Stufe {0}.'
        SafeFix = 'Sammelkorrektur: Die sichere Korrektur lässt sich projektweit anwenden (`--fix {0}`, MCP `fix_findings`, Befehl ' + [char]0x201E + 'Alle sicheren Treffer korrigieren ' + [char]0x2026 + [char]0x201C + ').'
        Overridden = 'Schweigt, solange {0} an ist.'; Or = ' oder '
        OptionHead = '| Option | Typ | Vorgabe | Bedeutung |'; Bad = 'Mit Treffer:'; Good = 'Richtig:'
        Categories = @{ 'bug' = 'Bug'; 'vulnerability' = 'Schwachstelle'; 'code-smell' = 'Code Smell'; 'security-hotspot' = 'Sicherheits-Hotspot' }
        Severities = @{ 'error' = 'Fehler'; 'warning' = 'Warnung'; 'information' = 'Information'; 'hint' = 'Hinweis' }
        GroupNames = $GroupNames; Levels = $LevelNames
    }
    'en' = @{
        Title = 'Check rules'; Generated = 'Generated by ``Tools/Update-RuleCatalog.ps1`` from the rule catalog. Do not edit by hand.'
        Other = '*Deutsche Fassung: [Regeln.md](../Regeln.md)*'
        Groups = 'Groups'; Group = 'Group'; RulesHead = 'Rules'; RuleCol = 'Rule'; NameCol = 'Name'; CategoryCol = 'Category'; SeverityCol = 'Severity'
        Anchor = 'group'; InGroup = 'Group'; Compiler = 'Matches the compiler message {0}.'; Level = 'Level {0}.'
        SafeFix = 'Bulk fix: the safe fix can be applied project-wide (`--fix {0}`, MCP `fix_findings`, command "Fix all safe findings ' + [char]0x2026 + '").'
        Overridden = 'Silent while {0} is on.'; Or = ' or '
        OptionHead = '| Option | Type | Default | Meaning |'; Bad = 'Flagged:'; Good = 'Correct:'
        Categories = @{ 'bug' = 'Bug'; 'vulnerability' = 'Vulnerability'; 'code-smell' = 'Code smell'; 'security-hotspot' = 'Security hotspot' }
        Severities = @{ 'error' = 'Error'; 'warning' = 'Warning'; 'information' = 'Information'; 'hint' = 'Hint' }
        GroupNames = [ordered]@{
            'find-bugs' = 'Find bugs'; 'exceptions' = 'Exceptions'; 'threads' = 'Threads'; 'database' = 'Database'
            'compiler' = 'Compiler ahead'; 'robustness' = 'Robustness and patterns'; 'performance' = 'Performance'
            'security' = 'Security'; 'components' = 'Components'; 'forms' = 'Forms and data'
            'architecture' = 'Architecture'; 'style' = 'Style and metrics'; 'packages' = 'Packages and tests'
            'internal' = 'Atlas internal'
        }
        Levels = @{
            'A' = 'A (the parser is enough)'
            'B' = 'B (name resolution across units)'
            'T' = 'T (needs expression types; can be turned off with "group:compiler": {"typeLevel": "off"})'
        }
    }
}

function New-RulesDoc([string] $Language) {
    $T = $DocTexts[$Language]
    $Translation = if ($Language -ne 'en' -and $Overlays.Contains($Language)) { $Overlays[$Language] | ConvertFrom-Json } else { $null }
    $Doc = New-Object System.Text.StringBuilder
    [void]$Doc.Append("# $($T.Title)`r`n`r`n$($T.Other)`r`n`r`n")
    [void]$Doc.Append("$($T.Generated -replace '``', '`')`r`n`r`n")
    $Rows = foreach ($Rule in $Base.rules) {
        $Translated = if ($Translation) { $Translation.rules | Where-Object { $_.id -eq $Rule.id } | Select-Object -First 1 } else { $null }
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
    [void]$Doc.Append("## $($T.Groups)`r`n`r`n| $($T.Group) | $($T.RulesHead) |`r`n|---|---|`r`n")
    foreach ($Group in $T.GroupNames.Keys) {
        $InGroup = @($Rows | Where-Object { $_.Rule.group -eq $Group })
        if ($InGroup.Count -eq 0) { continue }
        [void]$Doc.Append("| [$($T.GroupNames[$Group])](#$($T.Anchor)-$Group) | $($InGroup.Count) |`r`n")
    }
    foreach ($Group in $T.GroupNames.Keys) {
        $InGroup = @($Rows | Where-Object { $_.Rule.group -eq $Group })
        if ($InGroup.Count -eq 0) { continue }
        [void]$Doc.Append("`r`n<a id=""$($T.Anchor)-$Group""></a>`r`n### $($T.GroupNames[$Group])`r`n`r`n")
        [void]$Doc.Append("| $($T.RuleCol) | $($T.NameCol) | $($T.CategoryCol) | $($T.SeverityCol) |`r`n|---|---|---|---|`r`n")
        foreach ($Row in $InGroup) {
            [void]$Doc.Append("| [``$($Row.Rule.id)``](#$($Row.Rule.id)) | $($Row.Name) | $($T.Categories[$Row.Rule.category]) | $($T.Severities[$Row.Rule.severity]) |`r`n")
        }
    }
    [void]$Doc.Append("`r`n## $($T.RulesHead)`r`n")
    foreach ($Row in $Rows) {
        [void]$Doc.Append("`r`n<a id=""$($Row.Rule.id)""></a>`r`n### $($Row.Rule.id)`r`n`r`n")
        [void]$Doc.Append("**$($Row.Name)** · $($T.Categories[$Row.Rule.category]) · $($T.Severities[$Row.Rule.severity]) · $($T.InGroup) $($T.GroupNames[[string]$Row.Rule.group])`r`n`r`n")
        [void]$Doc.Append("$($Row.Description)`r`n`r`n")
        if ($Row.Rule.PSObject.Properties.Name -contains 'compilerCodes') {
            [void]$Doc.Append(($T.Compiler -f ((@($Row.Rule.compilerCodes) | ForEach-Object { '`' + $_ + '`' }) -join ', ')) + "`r`n`r`n")
        }
        if ($Row.Rule.PSObject.Properties.Name -contains 'level') {
            [void]$Doc.Append(($T.Level -f $T.Levels[[string]$Row.Rule.level]) + "`r`n`r`n")
        }
        if (($Row.Rule.PSObject.Properties.Name -contains 'safeFix') -and $Row.Rule.safeFix) {
            [void]$Doc.Append(($T.SafeFix -f $Row.Rule.id) + "`r`n`r`n")
        }
        if ($Row.Rule.PSObject.Properties.Name -contains 'overriddenBy') {
            [void]$Doc.Append(($T.Overridden -f ((@($Row.Rule.overriddenBy) | ForEach-Object { '[`' + $_ + '`](#' + $_ + ')' }) -join $T.Or)) + "`r`n`r`n")
        }
        if ($Row.Options.Count -gt 0) {
            [void]$Doc.Append("$($T.OptionHead)`r`n|---|---|---|---|`r`n")
            foreach ($Option in $Row.Options) {
                [void]$Doc.Append("| ``$($Option.Name)`` | $($Option.Kind) | ``$($Option.Default)`` | $($Option.Description) |`r`n")
            }
            [void]$Doc.Append("`r`n")
        }
        [void]$Doc.Append("$($T.Bad)`r`n`r`n``````pascal`r`n$($Row.Rule.bad -replace "`n", "`r`n")`r`n```````r`n`r`n")
        [void]$Doc.Append("$($T.Good)`r`n`r`n``````pascal`r`n$($Row.Rule.good -replace "`n", "`r`n")`r`n```````r`n")
    }
    $Doc.ToString()
}
$DocText = New-RulesDoc 'de'
$DocTextEn = New-RulesDoc 'en'

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
foreach ($Name in $PartUnits.Keys) {
    Sync-File (Join-Path $SourceDir "Rules/$Name.pas") $PartUnits[$Name]
}
# Teil-Units, die der Katalog nicht mehr braucht, und Teile, die im Package fehlen.
foreach ($File in Get-ChildItem (Join-Path $SourceDir 'Rules') -Filter "$PartPrefix*.pas") {
    if (($File.BaseName -match '^Atlas\.Common\.Rules\.Catalog\.Data\.[\w.]+$') -and -not $PartUnits.Contains($File.BaseName)) {
        if ($Check) {
            $Problems.Add("$($File.Name) gehört nicht mehr zum Katalog; pwsh Tools/Update-RuleCatalog.ps1 ausführen")
        }
        else {
            Remove-Item $File.FullName
        }
    }
}
$PackageDir = Join-Path $Root 'Packages/Atlas.Common'
$Dpk = Read-Text (Join-Path $PackageDir 'Atlas.Common.dpk')
$Dproj = Read-Text (Join-Path $PackageDir 'Atlas.Common.dproj')
foreach ($Name in $PartUnits.Keys) {
    if (-not $Dpk.Contains("$Name in 'Source\Rules\$Name.pas'")) {
        $Problems.Add("$Name fehlt in Atlas.Common.dpk")
    }
    if (-not $Dproj.Contains("Source\Rules\$Name.pas")) {
        $Problems.Add("$Name fehlt in Atlas.Common.dproj (DCCReference)")
    }
}
Sync-File $DocPath $DocText
Sync-File $DocPathEn $DocTextEn

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
$Security = $Counts['vulnerability'] + $Counts['security-hotspot']
$FourEn = @{ Find = "\*\*$Number check rules\*\* in four categories: $Number bugs, $Number code smells, $Number vulnerabilities, $Number security hotspots";
    Text = "**$Total check rules** in four categories: $($Counts['bug']) bugs, $($Counts['code-smell']) code smells, $($Counts['vulnerability']) vulnerabilities, $($Counts['security-hotspot']) security hotspots" }
$FourDe = @{ Find = "\*\*$Number Prüfregeln\*\* in vier Kategorien: $Number Fehler, $Number Code-Smells, $Number Schwachstellen, $Number Sicherheits-Hotspots";
    Text = "**$Total Prüfregeln** in vier Kategorien: $($Counts['bug']) Fehler, $($Counts['code-smell']) Code-Smells, $($Counts['vulnerability']) Schwachstellen, $($Counts['security-hotspot']) Sicherheits-Hotspots" }
# Kurzüberblick im README, ausführlich auf den Funktionsseiten (docs/features, #1458).
$ReadmeCounts = @(
    @{ File = 'README.md'; Patterns = @(
        @{ Find = "with $Number check rules,"; Text = "with $Total check rules," },
        @{ Find = "\*\*$Number check rules\*\* while you type: $Number bugs, $Number code smells, $Number security rules";
           Text = "**$Total check rules** while you type: $($Counts['bug']) bugs, $($Counts['code-smell']) code smells, $Security security rules" }) },
    @{ File = 'docs/features/en/Code-analysis.md'; Patterns = @($FourEn) },
    @{ File = 'README_DE.md'; Patterns = @(
        @{ Find = "mit $Number Prüfregeln,"; Text = "mit $Total Prüfregeln," },
        @{ Find = "\*\*$Number Prüfregeln\*\* schon beim Tippen: $Number Fehler, $Number Code-Smells, $Number Sicherheitsregeln";
           Text = "**$Total Prüfregeln** schon beim Tippen: $($Counts['bug']) Fehler, $($Counts['code-smell']) Code-Smells, $Security Sicherheitsregeln" }) },
    @{ File = 'docs/features/de/Code-Analyse.md'; Patterns = @($FourDe) }
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
