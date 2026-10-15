<#
.SYNOPSIS
    Erzeugt aus dem JSON-Schema von atlas.json die Doku, die Einstellungstabelle
    und die Schema-Unit des Plugins und prüft den Parser dagegen.

.DESCRIPTION
    Einzige Quelle ist schemas/atlas.schema.json (#265):
    - docs/Konfiguration.md: jeder Schlüssel mit Typ, Standardwert, erlaubten
      Werten und Beschreibung; verschachtelte Objekte als eigener Abschnitt.
    - docs/Einstellungen.md: Tabelle für das Einstellungs-Plugin (#227) aus den
      Angaben x-page, x-control, x-issue, x-commandLine und x-restart.
      x-quickToggle (mit x-plugin, x-caption, x-captionEn) an einer booleschen
      Einstellung macht sie zum Schnellschalter im Plugin (#604).
    - Wächter: Die Schlüssel in Atlas.Common.Configuration.Parser müssen genau
      denen im Schema entsprechen (Validierung und Schichtung).

    Mit -Check wird nichts geschrieben; Exit-Code 1, wenn eine Datei veraltet ist
    oder der Parser abweicht.

    Pflegeregel: Neue Einstellung -> Schema (mit x-page, x-control, x-issue),
    Parser, Test; dann dieses Skript ausführen.

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

$SchemaPath = Join-Path $Root 'schemas/atlas.schema.json'
$DocPath = Join-Path $Root 'docs/Konfiguration.md'
$TablePath = Join-Path $Root 'docs/Einstellungen.md'
$ParserPath = Join-Path $Root 'Packages/Atlas.Common/Source/Configuration/Atlas.Common.Configuration.Parser.pas'
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
[void]$Out.AppendLine('# Konfiguration: atlas.json')
[void]$Out.AppendLine()
[void]$Out.AppendLine('<!-- Erzeugt von Tools/Update-ConfigDoc.ps1 aus schemas/atlas.schema.json. Nicht von Hand bearbeiten. -->')
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
[void]$Out.AppendLine('  "$schema": "https://raw.githubusercontent.com/xKnockOut/Atlas/main/schemas/atlas.schema.json",')
[void]$Out.AppendLine('  "project": "App.dproj",')
[void]$Out.AppendLine('  "config": "Debug",')
[void]$Out.AppendLine('  "platform": "Win64",')
[void]$Out.AppendLine('  "rules": { "empty-except": "error" },')
[void]$Out.AppendLine('  "exclude": ["ThirdParty/**"]')
[void]$Out.AppendLine('}')
[void]$Out.AppendLine('```')
$Text = $Out.ToString().Replace("`r`n", "`n")

# --- Einstellungstabelle für das Plugin (#227) ---
$Table = New-Object System.Text.StringBuilder
[void]$Table.AppendLine('# Einstellungen')
[void]$Table.AppendLine()
[void]$Table.AppendLine('<!-- Erzeugt von Tools/Update-ConfigDoc.ps1 aus schemas/atlas.schema.json. Nicht von Hand bearbeiten. -->')
[void]$Table.AppendLine()
[void]$Table.AppendLine('Alle Einstellungen mit Seite und Bedienelement im Einstellungs-Plugin (#227). Einzelheiten zu Werten und Bedeutung stehen in [Konfiguration.md](Konfiguration.md).')
[void]$Table.AppendLine()
[void]$Table.AppendLine('| Seite | Einstellung | Standard | Quelle | Neustart | Bedienelement | Herkunft |')
[void]$Table.AppendLine('|---|---|---|---|---|---|---|')
foreach ($Name in $Schema['properties'].Keys) {
    if ($Name -eq '$schema') { continue }
    $P = $Schema['properties'][$Name]
    $Setting = '`' + $Name + '`'
    if (Has $P 'properties') { $Setting += ': ' + (($P['properties'].Keys | ForEach-Object { '`' + $_ + '`' }) -join ', ') }
    $Default = if ($P.ContainsKey('default')) { Format-Value $P['default'] } else { '–' }
    $Source = "atlas.json, Editor (``$Section.$Name``)"
    if (Has $P 'x-commandLine') { $Source += ', ``' + $P['x-commandLine'] + '``' }
    $Restart = if ((Has $P 'x-restart') -and $P['x-restart']) { 'ja' } else { 'nein' }
    $Page = if (Has $P 'x-page') { $P['x-page'] } else { '' }
    $Control = if (Has $P 'x-control') { $P['x-control'] } else { '' }
    $Issue = if (Has $P 'x-issue') { $P['x-issue'] } else { '' }
    [void]$Table.AppendLine("| $Page | $Setting | $Default | $Source | $Restart | $(Escape $Control) | $Issue |")
}
# Was kein Schlüssel in atlas.json ist, aber im Plugin erscheint.
[void]$Table.AppendLine('| Allgemein | Pfad zu `AtlasServer.exe` | – | Plugin (Registry `ServerPath`) | ja | Datei wählen, Version anzeigen | #12 |')
[void]$Table.AppendLine('| Baseline | `atlas-baseline.json` | – | Datei, `--baseline`, `--update-baseline` | nein | Anzahl Einträge, „Baseline neu erzeugen“, „Baseline löschen“ | #97 |')
[void]$Table.AppendLine('| Baseline | Unterdrückungen `lsp-ignore` | – | `--suppression-stats` | nein | Übersicht je Regel (nur Anzeige) | #147 |')
[void]$Table.AppendLine('| Speicher | Index-Cache löschen | – | `--clear-cache`, Befehl `atlas.server.clearIndex` (löschen und neu indizieren), `atlas.server.rebuildIndex` (nur neu indizieren) | nein | Knöpfe „Index löschen“ und „Index neu aufbauen“ | #184, #492 |')
[void]$Table.AppendLine('| Allgemein | Atlas-Feld in der Statusleiste (`statusField.enabled`), Kurztext (`statusField.showSummary`), Schnellschalter öffnen mit (`statusField.openToggles`: both, rightClick, doubleClick), ausgeblendete Zeilen (`statusField.hidden`) | an, an, both, – | Plugin (Registry `StatusField`, `StatusFieldSummary`, `StatusFieldToggles`, `StatusFieldHidden`) | nein | Kontrollkästchen, Kontrollkästchen, Auswahl, Textfeld mit Kennungen | #591 |')
[void]$Table.AppendLine('| Allgemein | Fortschritt beim Aufbau des Symbol-Index (`statusField.indexProgress`: statusField, menu, off); mit abgeschaltetem Statusfeld steht er im Menütitel | statusField | Plugin (Registry `IndexProgressPlace`) | nein | Auswahl | #492, #591 |')
[void]$Table.AppendLine('| Allgemein | Schnellschalter (#604): Fenster über dem Statusfeld (Rechtsklick oder Doppelklick) und Tastenkürzel; Schalter = jede boolesche Einstellung mit `x-quickToggle` (Plugin-Katalog und `atlas.schema.json`) | Strg+Umschalt+Alt+A | Plugin (Registry `QuickToggleKey`, `QuickToggleKeyPriority`) | nein | Taste auf der Seite „Tastenkonflikte“; „Alles aus für diese Sitzung“ ändert keine Einstellung | #604 |')
[void]$Table.AppendLine('| Allgemein | Abgesicherter Start nach einem Absturz: Rückfrage (`safeMode.askAfterCrash`), ohne Rückfrage nach zwei Abstürzen (`safeMode.autoAfterRepeatedCrash`), Taste beim Laden (`safeMode.startupKey`: shift, ctrl, none), längste Ladezeit (`safeMode.startupTimeoutMs`), gemerkte Einstellungsstände (`safeMode.keepSettingsHistory`) | an, an, shift, 10000, 5 | Plugin (Registry `SafeAskAfterCrash`, `SafeAutoAfterRepeatedCrash`, `SafeStartupKey`, `SafeStartupTimeoutMs`, `SafeKeepSettingsHistory`); Kommandozeile `-AtlasSafeMode`, Umgebungsvariable `ATLAS_SAFE_MODE=1` | nein | Kontrollkästchen, Kontrollkästchen, Auswahl, Zahl (1000–120000), Zahl (0–50) | #722 |')
[void]$Table.AppendLine('| Allgemein | Atlas-Änderungen über mehrere Dateien zurücknehmen: an/aus (`undo.multiFile`), Anzahl Sätze (`undo.multiFile.depth`), über Neustarts sichern (`undo.multiFile.persist`) bis höchstens MB (`undo.multiFile.maxSizeMb`), bei Konflikten (`undo.multiFile.onConflict`: partial, abort), neu angelegte Dateien (`undo.multiFile.newFiles`: recycleBin, delete, keep), Tasten Zurücknehmen und Wiederherstellen | an, 20, an, 50, partial, recycleBin, Strg+Alt+Z, Strg+Alt+Umschalt+Z | Plugin (Registry `UndoMultiFile`, `UndoMultiFileDepth`, `UndoMultiFilePersist`, `UndoMultiFileMaxSizeMb`, `UndoMultiFileOnConflict`, `UndoMultiFileNewFiles`, `UndoKey`, `RedoKey`); Sicherung in `%LOCALAPPDATA%\Atlas\undo` | nein | Kontrollkästchen, Zahl (1–200), Kontrollkästchen, Zahl (1–1024), Auswahl, Auswahl, Tastenkürzel, Tastenkürzel | #721 |')
[void]$Table.AppendLine('| Allgemein | Nach Zustimmung beim ersten Start höchstens einmal täglich auf eine neue Atlas-Version prüfen (`updates.check`); übertragen werden nur Atlas- und IDE-Version, ein Hinweis erscheint in der Meldungsansicht | aus | Plugin (Registry `UpdatesCheck`); Zustand in `%LOCALAPPDATA%\Atlas\updates.json` | nein | Kontrollkästchen | #495 |')
[void]$Table.AppendLine('| Allgemein | Fehlerbericht (*Atlas › Fehlerbericht erstellen…*) anonymisieren: Pfade unter dem Projekt zu `<ws>`, andere Pfade zu `<pfad>`, Benutzername und Bezeichner im Protokoll ersetzen (`diagnostics.bugReport.anonymize`) | an | Plugin (Registry `BugReportAnonymize`) | nein | Kontrollkästchen | #108 |')
$TableText = $Table.ToString().Replace("`r`n", "`n")

# --- Wächter: Schlüssel im Parser ---
$Problems = New-Object System.Collections.Generic.List[string]
$SchemaKeys = @($Schema['properties'].Keys | Where-Object { $_ -ne '$schema' } | Sort-Object)
$ParserText = [IO.File]::ReadAllText($ParserPath, $Utf8).Replace("`r`n", "`n")
$Starts = [regex]::Matches($ParserText, "Key = 'delphiVersion'")
if ($Starts.Count -lt 2) { $Problems.Add('Parser: Validierung und Schichtung nicht gefunden') }
foreach ($Start in $Starts) {
    $Stop = $ParserText.IndexOf("`nend;", $Start.Index)
    $Chain = $ParserText.Substring($Start.Index, $Stop - $Start.Index)
    $Keys = @([regex]::Matches($Chain, "Key = '([A-Za-z]+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $Line = $ParserText.Substring(0, $Start.Index).Split("`n").Count
    foreach ($Key in $SchemaKeys) { if ($Keys -cnotcontains $Key) { $Problems.Add("Parser Zeile ${Line}: Schlüssel ""$Key"" aus dem Schema fehlt") } }
    foreach ($Key in $Keys) { if ($SchemaKeys -cnotcontains $Key) { $Problems.Add("Parser Zeile ${Line}: Schlüssel ""$Key"" fehlt im Schema") } }
}
foreach ($Name in $SchemaKeys) {
    $P = $Schema['properties'][$Name]
    if (Has $P 'properties') {
        foreach ($Sub in $P['properties'].Keys) {
            if (-not $ParserText.Contains("'$Sub'")) { $Problems.Add("Parser: ""$Name.$Sub"" aus dem Schema wird nicht gelesen") }
        }
    }
    foreach ($Meta in 'x-page', 'x-control', 'x-issue') {
        if (-not (Has $P $Meta)) { $Problems.Add("Schema: ""$Name"" ohne $Meta") }
    }
}

# --- Schreiben oder prüfen ---
$Targets = @(
    @{ Path = $DocPath; Text = $Text; Name = 'docs/Konfiguration.md' },
    @{ Path = $TablePath; Text = $TableText; Name = 'docs/Einstellungen.md' }
)
foreach ($Target in $Targets) {
    $Current = if (Test-Path $Target.Path) { [IO.File]::ReadAllText($Target.Path, $Utf8).Replace("`r`n", "`n") } else { '' }
    if ($Current -eq $Target.Text) { continue }
    if ($Check) { $Problems.Add("$($Target.Name) ist veraltet: pwsh Tools/Update-ConfigDoc.ps1 ausführen") }
    else {
        [IO.File]::WriteAllText($Target.Path, $Target.Text, $Utf8)
        Write-Host "Geschrieben: $($Target.Path)"
    }
}
# --- Schema für den Einstellungsdialog im Plugin (#227): UTF-8 mit BOM, CRLF ---
$SchemaUnitPath = Join-Path $Root 'Packages/Atlas.IDE.Expert/Source/Core/Settings/Atlas.Core.Settings.SchemaData.pas'
$SchemaLines = [IO.File]::ReadAllText($SchemaPath, $Utf8).TrimStart([char]0xFEFF).Replace("`r`n", "`n").TrimEnd("`n").Split("`n")
$Unit = New-Object System.Text.StringBuilder
foreach ($Line in @(
    'unit Atlas.Core.Settings.SchemaData;', '',
    '// Erzeugt von Tools/Update-ConfigDoc.ps1 aus schemas/atlas.schema.json;',
    '// nicht von Hand ändern. JSON-Schema von atlas.json für den Einstellungsdialog (#227).', '',
    'interface', '', '/// <summary>Inhalt von atlas.schema.json.</summary>', 'function AtlasSchemaJson: string;', '',
    'implementation', '', 'const', "  Lines: array[0..$($SchemaLines.Count - 1)] of string = (")) { [void]$Unit.Append($Line + "`r`n") }
for ($Index = 0; $Index -lt $SchemaLines.Count; $Index++) {
    $Escaped = $SchemaLines[$Index].Replace("'", "''")
    $Pieces = @()
    for ($At = 0; $At -lt $Escaped.Length; $At += 200) { $Pieces += "'" + $Escaped.Substring($At, [Math]::Min(200, $Escaped.Length - $At)) + "'" }
    if ($Pieces.Count -eq 0) { $Pieces = @("''") }
    $End = if ($Index -eq $SchemaLines.Count - 1) { ');' } else { ',' }
    [void]$Unit.Append('    ' + ($Pieces -join ' + ') + $End + "`r`n")
}
foreach ($Line in @('', 'function AtlasSchemaJson: string;', 'var', '  Line: string;', 'begin', "  Result := '';",
    '  for Line in Lines do', '    Result := Result + Line + #10;', 'end;', '', 'end.')) { [void]$Unit.Append($Line + "`r`n") }
$UnitText = $Unit.ToString()
$CurrentUnit = if (Test-Path $SchemaUnitPath) { [IO.File]::ReadAllText($SchemaUnitPath, $Utf8).TrimStart([char]0xFEFF) } else { '' }
if ($CurrentUnit -ne $UnitText) {
    if ($Check) { $Problems.Add('Atlas.Core.Settings.SchemaData.pas ist veraltet: pwsh Tools/Update-ConfigDoc.ps1 ausführen') }
    else {
        [IO.File]::WriteAllText($SchemaUnitPath, $UnitText, (New-Object System.Text.UTF8Encoding($true)))
        Write-Host "Geschrieben: $SchemaUnitPath"
    }
}

if ($Problems.Count -gt 0) {
    foreach ($Problem in $Problems) { Write-Error $Problem -ErrorAction Continue }
    exit 1
}
Write-Host 'Schema, Parser, Schema-Unit und Doku stimmen überein.'
exit 0
