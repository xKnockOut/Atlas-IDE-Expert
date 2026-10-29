<#
.SYNOPSIS
    Übersetzt jeden Fall aus Tests/Compilermeldungen einzeln mit dcc und schreibt alle Meldungen in eine Tabelle;
    auf Wunsch prüft es die Fälle danach mit Atlas.

.DESCRIPTION
    Jeder Fall löst genau eine Meldung von dcc aus (Warnung, Hinweis, Fehler oder fataler Fehler). Damit ein
    Fehler die übrigen Fälle nicht verdeckt, bekommt jeder Fall ein eigenes kleines Projekt, das dieses Skript in
    Output/Compilermeldungen/Projekte erzeugt:

    - Cm.<Code>.pas: ein Konsolenprogramm, das die Unit mit "in" einbindet; Hilfsunits findet es über den
      Suchpfad Faelle.
    - Cm<Code>.dpr und Cm<Code>.dpk: das Programm bzw. Paket selbst, "in"-Pfade zeigen auf Faelle.

    Kopfzeilen eines Falls:
      // Plattform: Win32     nur auf dieser Plattform bauen (sonst alle aus -Platforms)
      // Schalter: --doc      zusätzliche Option für dcc (DCC_AdditionalSwitches); --doc wird zu
                              DCC_OutputXMLDocumentation samt eingeschalteten DCC_XML_*-Warnungen

    Ablauf wie Tools/Build-DccFaelle.ps1: eigene Scratch-IDE über cc.ps1 starten (pid darf zu keiner schon
    laufenden IDE gehören), jedes Projekt mit "build" übersetzen, die dcc-Zeilen aus dem logFile übernehmen,
    am Ende "quit". "build -Project" baut nur offene Projekte; daher öffnet die IDE vorab die erzeugte Gruppe
    Projekte/Compilermeldungen.groupproj, und das Skript wartet, bis status.json alle Projekte nennt.

    Mit -IdeProfile <Name> startet das Skript bds.exe -r <Name> selbst (cc.ps1 start nimmt keine Argumente),
    mit geerbter Marke CLAUDE_COMPILE_OWNED, damit "quit" die IDE beenden darf. Das Profil muss es unter
    HKCU\Software\Embarcadero\<Name>\37.0 geben und das Claude-Compile-Paket laden; Atlas braucht es nicht.

    Listen aus "pwsh -File" ('a','b' kommt als "a,b" an) teilt das Skript an Kommas; aus PowerShell heraus
    besser "pwsh -Command { & ./Tools/Build-Compilermeldungen.ps1 ... }".

    Ergebnis: Output/Compilermeldungen/dcc.tsv mit den Spalten Fall, Plattform, Ok, Datei, Zeile, Code, Art, Text.
    Ein Fall ohne dcc-Meldung steht mit leerem Code in der Tabelle.

    Mit -Dcc übersetzt das Skript ohne IDE mit den Kommandozeilen-Compilern dcc32.exe und dcc64.exe der mit
    -BdsVersion gewählten Delphi-Version (Vorgabe 37.0 = Delphi 13, 23.0 = Delphi 12); dann braucht es weder cc.ps1
    noch ein Registry-Profil. Die Starter-Edition hat keine Kommandozeilen-Compiler. -ResultFile legt die Tabelle
    an anderer Stelle ab, etwa für einen Lauf mit Delphi 12 neben dem mit Delphi 13 (#1383).

    Mit -AtlasServer prüft das Skript danach Tests/Compilermeldungen mit "AtlasServer --check" (Profile strict
    und standard) und legt die JSON-Ergebnisse daneben ab. Tools/Compare-Compilermeldungen.py vergleicht beides.

    Exit-Code 0: alle Projekte gebaut (mit oder ohne Meldungen). 3: Aufruf- oder Umgebungsfehler.

.EXAMPLE
    pwsh Tools/Build-Compilermeldungen.ps1
    pwsh Tools/Build-Compilermeldungen.ps1 -Platforms Win32 -Cases 'Cm.W1*'
    pwsh Tools/Build-Compilermeldungen.ps1 -AtlasServer Output\Win64\Debug\Bin\AtlasServer.exe
    pwsh Tools/Build-Compilermeldungen.ps1 -Dcc -BdsVersion 23.0 -ResultFile Output\Compilermeldungen\dcc-delphi12.tsv
    pwsh Tools/Build-Compilermeldungen.ps1 -BdsVersion 23.0 -IdeProfile AtlasCm12 -ResultFile Output\Compilermeldungen\dcc-delphi12.tsv
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [string] $CcScript = $(if ($env:CC_SCRIPT) { $env:CC_SCRIPT } else { 'C:\Projekte\IDE-Plugins\Claude-Compile\cc.ps1' }),
    [string[]] $Platforms = @('Win32', 'Win64'),
    # Dateimuster der Fälle (ohne Endung), etwa 'Cm.W1*' oder 'CmE2200'.
    [string[]] $Cases = @('*'),
    # Eigenes Registry-Profil der Scratch-IDE (bds -r <Profil>), etwa 'AtlasCm'. cc.ps1 start kennt keine
    # Startargumente; mit Profil startet das Skript bds.exe selbst und öffnet das Projekt mit cc.ps1 open.
    [string] $IdeProfile = '',
    # Delphi-Version als BDS-Nummer: 37.0 = Delphi 13, 23.0 = Delphi 12 (Registry-Pfad der IDE und der Compiler).
    [string] $BdsVersion = '37.0',
    # Ohne IDE mit dcc32.exe/dcc64.exe übersetzen (nicht in der Starter-Edition).
    [switch] $Dcc,
    # Ergebnistabelle; leer = Output/Compilermeldungen/dcc.tsv.
    [string] $ResultFile = '',
    [int] $StartTimeoutSeconds = 300,
    [string] $AtlasServer = '',
    [switch] $SkipBuild,
    [int] $QuitAttempts = 10,
    [int] $QuitDelaySeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# "pwsh -File" übergibt 'a','b' als einen String "a,b".
$Cases = @($Cases | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$Platforms = @($Platforms | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$TestDir = Join-Path $Root 'Tests/Compilermeldungen'
$CaseDir = Join-Path $TestDir 'Faelle'
$OutDir = Join-Path $Root 'Output/Compilermeldungen'
$ProjectDir = Join-Path $OutDir 'Projekte'
if (-not $ResultFile) { $ResultFile = Join-Path $OutDir 'dcc.tsv' }
$ResultFile = [System.IO.Path]::GetFullPath($ResultFile)
# "[dcc32 Fehler] Cm.E2003.pas(12): E2003 Undeklarierter Bezeichner: 'X'"
$DccPattern = '\[dcc\w*\s+([^\]]+)\]\s*(?:([^\s(][^(]*)\((\d+)\))?:?\s*(?:([EWHFX]\d{4})\s+)?(.*)$'
# Kommandozeile: "Cm.W1036.pas(14) Warnung: W1036 ..." bzw. "Fatal: F2613 ..." ohne Datei.
$DccConsolePattern = '^(?:(.+?)\((\d+)\)\s+)?([^:()]+?):\s+([EWHFX]\d{4})\s+(.*)$'
$CasePattern = '^Cm\.?[EWHF]\d{4}'
# XML-Warnungen W1201-W1208 (DCC_XML_* in der .dproj, -W+XML_* auf der Kommandozeile).
$XmlWarnings = @('WHITESPACE_NOT_ALLOWED', 'UNKNOWN_ENTITY', 'INVALID_NAME_START', 'INVALID_NAME', 'EXPECTED_CHARACTER',
    'CREF_NO_RESOLVE', 'NO_PARM', 'NO_MATCHING_PARM')

function Write-Step([string] $Text) {
    Write-Host "== $Text"
}

function Get-IdeProcessIds {
    @(Get-Process -Name 'bds' -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
}

function Invoke-Cc([string[]] $Arguments) {
    # Benannte Parameter als Hashtable: Beim Splatting eines Arrays käme "-Project" als Wert an.
    $named = @{}
    $positional = @()
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $arg = $Arguments[$i]
        if ($arg -match '^-(\w+)$') {
            # Merken, bevor der nächste Vergleich $Matches überschreibt (Schalter vor Schalter).
            $name = $Matches[1]
            if ($i + 1 -lt $Arguments.Count -and $Arguments[$i + 1] -notmatch '^-\w+$') {
                $named[$name] = $Arguments[$i + 1]
                $i++
            } else {
                $named[$name] = $true
            }
        } else {
            $positional += $arg
        }
    }
    # StrictMode dieses Skripts nicht an cc.ps1 vererben (liest optionale Felder aus status.json).
    $output = & { Set-StrictMode -Off; & $CcScript @positional @named } *>&1 | Out-String
    [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE }
}

function Get-BdsRoot {
    (Get-ItemProperty -Path "HKCU:\Software\Embarcadero\BDS\$BdsVersion" -Name RootDir).RootDir
}

# Startet bds.exe mit eigenem Profil. CLAUDE_COMPILE_OWNED erbt nur dieser Prozess; ohne die Marke beendet
# cc.ps1 quit die IDE nicht. Liefert die pid, sobald das Plugin seinen Briefkasten angelegt hat.
function Start-ProfileIde([string] $Group) {
    $bds = Join-Path (Get-BdsRoot) 'bin\bds.exe'
    if (-not (Test-Path "HKCU:\Software\Embarcadero\$IdeProfile\$BdsVersion\Known Packages")) {
        throw "Registry-Profil $IdeProfile fehlt (HKCU\Software\Embarcadero\$IdeProfile\$BdsVersion)"
    }
    $env:CLAUDE_COMPILE_OWNED = '1'
    try { $proc = Start-Process -FilePath $bds -ArgumentList @('-r', $IdeProfile) -PassThru }
    finally { Remove-Item Env:\CLAUDE_COMPILE_OWNED -ErrorAction SilentlyContinue }
    Write-Host "bds.exe -r $IdeProfile gestartet (pid $($proc.Id))"
    $status = Join-Path $env:LOCALAPPDATA "ClaudeCompile\instances\$($proc.Id)\status.json"
    $t0 = Get-Date
    while (-not (Test-Path $status)) {
        if ($proc.HasExited) { throw 'Die IDE hat sich vor dem Briefkasten beendet' }
        if (((Get-Date) - $t0).TotalSeconds -gt $StartTimeoutSeconds) { throw "Kein Briefkasten nach $StartTimeoutSeconds s" }
        Start-Sleep -Milliseconds 500
    }
    Start-Sleep -Seconds 3
    $open = Invoke-Cc @('open', '-Project', $Group, '-Instance', "$($proc.Id)")
    Write-Host $open.Output
    $proc.Id
}

# "open" antwortet, bevor die IDE die Gruppe geladen hat. Warten, bis status.json alle Projekte nennt.
function Wait-ProjectsOpen([int] $IdeId, [string[]] $Expected) {
    $status = Join-Path $env:LOCALAPPDATA "ClaudeCompile\instances\$IdeId\status.json"
    $Expected = @($Expected | ForEach-Object { [System.IO.Path]::GetFullPath($_) })
    $missing = $Expected
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $StartTimeoutSeconds) {
        $open = @()
        try { $open = @((Get-Content -Path $status -Raw | ConvertFrom-Json).openProjects | ForEach-Object { $_.file }) } catch { }
        $missing = @($Expected | Where-Object { $open -notcontains $_ })
        if ($missing.Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    throw "Nach $StartTimeoutSeconds s fehlen noch $($missing.Count) Projekte in der IDE, etwa $($missing[0])"
}

function ConvertFrom-BuildOutput([string] $Output) {
    $start = $Output.IndexOf('{')
    if ($start -lt 0) { return $null }
    try { $Output.Substring($start) | ConvertFrom-Json } catch { $null }
}

function Get-Property($Object, [string] $Name) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { $Object.$Name } else { $null }
}

# Kopfzeile "// <Name>: <Wert>" eines Falls, sonst ''.
function Get-CaseHeader([string] $Path, [string] $Name) {
    foreach ($line in Get-Content -Path $Path -Encoding UTF8 -TotalCount 15) {
        if ($line -match "^//\s*$Name\s*:\s*(.+)$") { return $Matches[1].Trim() }
    }
    ''
}

function Write-Utf8Bom([string] $Path, [string] $Text) {
    $crlf = ($Text -replace "`r?`n", "`r`n")
    [System.IO.File]::WriteAllText($Path, $crlf, [System.Text.UTF8Encoding]::new($true))
}

function New-CaseProject($Case) {
    $dir = Join-Path $ProjectDir $Case.Stem
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $isPackage = $Case.Extension -eq '.dpk'
    if ($Case.Extension -eq '.pas') {
        $name = 'P' + ($Case.Stem -replace '\W', '')
        $main = "$name.dpr"
        Write-Utf8Bom (Join-Path $dir $main) @"
program $name;

{`$APPTYPE CONSOLE}

uses
  $($Case.Stem) in '$($Case.Path)';

begin
end.
"@
    } else {
        $name = $Case.Stem
        $main = "$name$($Case.Extension)"
        # Relative "in"-Pfade auf den Ordner der Fälle umbiegen; die Zeilennummern bleiben gleich.
        $text = [System.IO.File]::ReadAllText($Case.Path)
        $text = [regex]::Replace($text, "in '([^':\\]+)'", { param($m) "in '" + (Join-Path $CaseDir $m.Groups[1].Value) + "'" })
        Write-Utf8Bom (Join-Path $dir $main) $text
    }
    $switches = Get-CaseHeader $Case.Path 'Schalter'
    # --doc entspricht in der IDE "XML-Dokumentation erzeugen"; als Zusatzschalter reicht es die IDE nicht weiter.
    $xmlDoc = $(if ($switches -match '(^|\s)--doc(\s|$)') { 'true' } else { 'false' })
    $switches = ($switches -replace '(^|\s)--doc(?=\s|$)', '').Trim()
    # W1201-W1208 ausdrücklich als Warnung, unabhängig von den Vorgaben des Profils.
    $xmlWarnings = $(if ($xmlDoc -eq 'true') {
        ($XmlWarnings | ForEach-Object { "        <DCC_XML_$_>true</DCC_XML_$_>" }) -join "`r`n"
    } else { '' })
    $appType = $(if ($isPackage) { 'Package' } else { 'Console' })
    $projectType = $(if ($isPackage) { 'Package' } else { 'Application' })
    $guid = [guid]::NewGuid().ToString('B').ToUpperInvariant()
    $dproj = Join-Path $dir "$name.dproj"
    Write-Utf8Bom $dproj @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <ProjectGuid>$guid</ProjectGuid>
        <MainSource>$main</MainSource>
        <ProjectVersion>20.3</ProjectVersion>
        <FrameworkType>None</FrameworkType>
        <AppType>$appType</AppType>
        <Base>True</Base>
        <Config Condition="'`$(Config)'==''">Base</Config>
        <Platform Condition="'`$(Platform)'==''">Win32</Platform>
        <TargetedPlatforms>3</TargetedPlatforms>
        <ProjectName Condition="'`$(ProjectName)'==''">$name</ProjectName>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Config)'=='Base' or '`$(Base)'!=''">
        <Base>true</Base>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Base)'!=''">
        <DCC_Namespace>System;Winapi;`$(DCC_Namespace)</DCC_Namespace>
        <DCC_UnitSearchPath>$CaseDir;`$(DCC_UnitSearchPath)</DCC_UnitSearchPath>
        <DCC_DcuOutput>.\Dcu\`$(Platform)</DCC_DcuOutput>
        <DCC_ExeOutput>.\Bin\`$(Platform)</DCC_ExeOutput>
        <DCC_BplOutput>.\Bin\`$(Platform)</DCC_BplOutput>
        <DCC_DcpOutput>.\Dcu\`$(Platform)</DCC_DcpOutput>
        <DCC_AdditionalSwitches>$switches</DCC_AdditionalSwitches>
        <DCC_OutputXMLDocumentation>$xmlDoc</DCC_OutputXMLDocumentation>
$xmlWarnings
        <SanitizedProjectName>$name</SanitizedProjectName>
    </PropertyGroup>
    <ItemGroup>
        <DelphiCompile Include="`$(MainSource)">
            <MainSource>MainSource</MainSource>
        </DelphiCompile>
        <BuildConfiguration Include="Base">
            <Key>Base</Key>
        </BuildConfiguration>
    </ItemGroup>
    <ProjectExtensions>
        <Borland.Personality>Delphi.Personality.12</Borland.Personality>
        <Borland.ProjectType>$projectType</Borland.ProjectType>
        <BorlandProject>
            <Delphi.Personality>
                <Source>
                    <Source Name="MainSource">$main</Source>
                </Source>
            </Delphi.Personality>
            <Platforms>
                <Platform value="Win32">True</Platform>
                <Platform value="Win64">True</Platform>
            </Platforms>
        </BorlandProject>
        <ProjectFileVersion>12</ProjectFileVersion>
    </ProjectExtensions>
    <Import Project="`$(BDS)\Bin\CodeGear.Delphi.Targets" Condition="Exists('`$(BDS)\Bin\CodeGear.Delphi.Targets')"/>
    <Import Project="`$(APPDATA)\Embarcadero\`$(BDSAPPDATABASEDIR)\`$(PRODUCTVERSION)\UserTools.proj" Condition="Exists('`$(APPDATA)\Embarcadero\`$(BDSAPPDATABASEDIR)\`$(PRODUCTVERSION)\UserTools.proj')"/>
</Project>
"@
    $dproj
}

function Get-BuildRows($Case, [string] $Platform, $Build) {
    $result = ConvertFrom-BuildOutput $Build.Output
    $ok = Get-Property $result 'ok'
    $logFile = Get-Property $result 'logFile'
    $rows = @()
    if ($logFile -and (Test-Path $logFile)) {
        foreach ($line in Get-Content -Path $logFile) {
            if ($line -notmatch $DccPattern) { continue }
            $file = $(if ($Matches[2]) { Split-Path -Leaf $Matches[2].Trim() } else { '' })
            $rows += [pscustomobject]@{
                Fall = $Case.Stem; Plattform = $Platform; Ok = "$ok"; Datei = $file; Zeile = "$($Matches[3])"
                Code = "$($Matches[4])"; Art = $Matches[1].Trim(); Text = $Matches[5].Trim()
            }
        }
    }
    if ($rows.Count -eq 0) {
        # Das Plugin kann die Fehlertexte nicht immer lesen; dann die rohe Ausgabe mitgeben.
        $text = $(if ($ok) { '' } else { ($Build.Output -split "`r?`n" | Where-Object { $_.Trim() -ne '' }) -join ' | ' })
        $rows += [pscustomobject]@{
            Fall = $Case.Stem; Plattform = $Platform; Ok = "$ok"; Datei = ''; Zeile = ''; Code = ''; Art = ''; Text = $text
        }
    }
    $rows
}

# Übersetzt das Projekt eines Falls mit dcc32.exe/dcc64.exe (-Dcc) und liefert die Zeilen für dcc.tsv.
function Invoke-DccBuild($Case, [string] $Platform, [string] $Dproj) {
    $dir = Split-Path -Parent $Dproj
    $main = Join-Path $dir ([xml] (Get-Content -Path $Dproj -Raw)).Project.PropertyGroup[0].MainSource
    $exe = Join-Path (Get-BdsRoot) $(if ($Platform -eq 'Win64') { 'bin\dcc64.exe' } else { 'bin\dcc32.exe' })
    $dcu = Join-Path $dir "Dcu\$Platform"
    $bin = Join-Path $dir "Bin\$Platform"
    New-Item -ItemType Directory -Force -Path $dcu, $bin | Out-Null
    $arguments = @('-B', '-Q', '-NSSystem;Winapi', "-U$CaseDir", "-I$CaseDir", "-NU$dcu", "-E$bin", "-LE$bin", "-LN$dcu")
    $switches = Get-CaseHeader $Case.Path 'Schalter'
    if ($switches -match '(^|\s)--doc(\s|$)') {
        $arguments += @('--doc') + @($XmlWarnings | ForEach-Object { "-W+XML_$_" })
    }
    $arguments += @(($switches -replace '(^|\s)--doc(?=\s|$)', '').Trim() -split '\s+' | Where-Object { $_ })
    $output = @(& $exe @arguments $main 2>&1 | ForEach-Object { "$_" })
    $ok = $LASTEXITCODE -eq 0
    $rows = @()
    foreach ($line in $output) {
        if ($line -notmatch $DccConsolePattern) { continue }
        $file = $(if ($Matches[1]) { Split-Path -Leaf $Matches[1].Trim() } else { '' })
        $rows += [pscustomobject]@{
            Fall = $Case.Stem; Plattform = $Platform; Ok = "$ok"; Datei = $file; Zeile = "$($Matches[2])"
            Code = "$($Matches[4])"; Art = $Matches[3].Trim(); Text = $Matches[5].Trim()
        }
    }
    if ($rows.Count -eq 0) {
        $text = $(if ($ok) { '' } else { ($output | Where-Object { $_.Trim() -ne '' }) -join ' | ' })
        $rows += [pscustomobject]@{
            Fall = $Case.Stem; Plattform = $Platform; Ok = "$ok"; Datei = ''; Zeile = ''; Code = ''; Art = ''; Text = $text
        }
    }
    $rows
}

function Invoke-Atlas([string] $RuleProfile) {
    $target = Join-Path $TestDir 'Compilermeldungen.dproj'
    $output = Join-Path $OutDir "atlas-$RuleProfile.json"
    Write-Step "Atlas --check ($RuleProfile)"
    & $AtlasServer --check $target --format json --fail-on never --profile $RuleProfile --output $output 2>&1 |
        ForEach-Object { Write-Host $_ }
    # Programme und Pakete einzeln: Die .dproj bindet nur Units ein.
    $extra = @()
    foreach ($file in Get-ChildItem -Path $CaseDir -File | Where-Object { $_.Extension -in '.dpr', '.dpk' }) {
        $single = Join-Path $OutDir "atlas-$RuleProfile-$($file.BaseName).json"
        & $AtlasServer --check $file.FullName --format json --fail-on never --profile $RuleProfile --output $single 2>&1 |
            Out-Null
        $extra += $single
    }
    Write-Host "  $output (+ $($extra.Count) Einzeldateien)"
}

# Schreibt die Zeilen nach $ResultFile; Nachlauf einzelner Fälle (-Cases): die Zeilen der übrigen Fälle aus dem
# letzten Lauf bleiben stehen.
function Write-Result($Rows) {
    $header = "Fall`tPlattform`tOk`tDatei`tZeile`tCode`tArt`tText"
    $lines = @($header) + @($Rows | ForEach-Object {
        @($_.Fall, $_.Plattform, $_.Ok, $_.Datei, $_.Zeile, $_.Code, $_.Art, ($_.Text -replace "`t", ' ')) -join "`t"
    })
    if (($Cases -join ',') -ne '*' -and (Test-Path $ResultFile)) {
        $built = @{}
        foreach ($case in $caseFiles) { $built[$case.Stem] = $true }
        $kept = @(Get-Content -Path $ResultFile -Encoding UTF8 | Select-Object -Skip 1 |
            Where-Object { -not $built.ContainsKey(($_ -split "`t")[0]) })
        $lines = @($header) + $kept + @($lines | Select-Object -Skip 1)
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ResultFile) | Out-Null
    Set-Content -Path $ResultFile -Value $lines -Encoding UTF8
    Write-Step "dcc-Ergebnis in $ResultFile ($(@($Rows).Count) neue Zeilen)"
}

foreach ($path in @($CaseDir)) {
    if (-not (Test-Path $path)) {
        Write-Error "Nicht gefunden: $path" -ErrorAction Continue
        exit 3
    }
}
New-Item -ItemType Directory -Force -Path $ProjectDir | Out-Null

$caseFiles = @(Get-ChildItem -Path $CaseDir -File |
    Where-Object { $_.Name -match $CasePattern -and $_.Extension -in '.pas', '.dpr', '.dpk' } |
    Where-Object { $file = $_; @($Cases | Where-Object { $file.BaseName -like $_ }).Count -gt 0 } |
    Sort-Object Name |
    ForEach-Object {
        [pscustomobject]@{
            Stem = $_.BaseName; Extension = $_.Extension; Path = $_.FullName
            Plattform = (Get-CaseHeader $_.FullName 'Plattform')
        }
    })

$exitCode = 0
if (-not $SkipBuild -and $Dcc) {
    foreach ($compiler in @('bin\dcc32.exe', 'bin\dcc64.exe')) {
        $path = Join-Path (Get-BdsRoot) $compiler
        if (-not (Test-Path $path)) {
            Write-Error "Nicht gefunden: $path (Kommandozeilen-Compiler fehlen, etwa in der Starter-Edition)" -ErrorAction Continue
            exit 3
        }
    }
    Write-Step "$($caseFiles.Count) Fälle mit dcc (BDS $BdsVersion)"
    $rows = @()
    $number = 0
    foreach ($case in $caseFiles) {
        $number++
        $dproj = New-CaseProject $case
        $targets = $(if ($case.Plattform) { @($case.Plattform) } else { $Platforms })
        foreach ($platform in $targets) {
            Write-Step "[$number/$($caseFiles.Count)] $($case.Stem) ($platform)"
            $rows += Invoke-DccBuild $case $platform $dproj
        }
    }
    Write-Result $rows
} elseif (-not $SkipBuild) {
    if (-not (Test-Path $CcScript)) {
        Write-Error "Nicht gefunden: $CcScript" -ErrorAction Continue
        exit 3
    }
    Write-Step "$($caseFiles.Count) Fälle, Projekte erzeugen"
    $projects = @{}
    foreach ($case in $caseFiles) {
        $projects[$case.Stem] = New-CaseProject $case
    }
    # "build -Project" baut nur Projekte, die in der IDE offen sind. Einzeln nachgeöffnete Projekte landen in
    # einer unbenannten Gruppe, und beim Beenden fragt die IDE nach "speichern unter"; daher eine Gruppe auf Platte.
    $group = Join-Path $ProjectDir 'Compilermeldungen.groupproj'
    $relative = @($caseFiles | ForEach-Object { [System.IO.Path]::GetRelativePath($ProjectDir, $projects[$_.Stem]) })
    $items = ($relative | ForEach-Object { "        <Projects Include=""$_""/>" }) -join "`r`n"
    # Ohne die Targets lädt die IDE die Gruppe leer.
    $targetNames = @($relative | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) })
    $targets = (@(for ($i = 0; $i -lt $relative.Count; $i++) {
        $n = $targetNames[$i]; $r = $relative[$i]
        "    <Target Name=""$n"">`r`n        <MSBuild Projects=""$r""/>`r`n    </Target>"
        "    <Target Name=""${n}:Clean"">`r`n        <MSBuild Projects=""$r"" Targets=""Clean""/>`r`n    </Target>"
        "    <Target Name=""${n}:Make"">`r`n        <MSBuild Projects=""$r"" Targets=""Make""/>`r`n    </Target>"
    }) + @(
        "    <Target Name=""Build"">`r`n        <CallTarget Targets=""$($targetNames -join ';')""/>`r`n    </Target>"
    )) -join "`r`n"
    Write-Utf8Bom $group @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <ProjectGuid>$([guid]::NewGuid().ToString('B').ToUpperInvariant())</ProjectGuid>
    </PropertyGroup>
    <ItemGroup>
$items
    </ItemGroup>
    <ProjectExtensions>
        <Borland.Personality>Default.Personality.12</Borland.Personality>
        <Borland.ProjectType/>
        <BorlandProject>
            <Default.Personality/>
        </BorlandProject>
    </ProjectExtensions>
$targets
</Project>
"@

    $rows = @()
    $ideId = $null
    $before = Get-IdeProcessIds
    try {
        Write-Step 'Scratch-IDE starten'
        if ($IdeProfile) {
            $ideId = Start-ProfileIde $group
        } else {
            $start = Invoke-Cc @('start', '-Project', $group)
            Write-Host $start.Output
            if ($start.Output -notmatch 'pid\D*(\d+)') {
                Write-Error 'pid der Scratch-IDE nicht in der Ausgabe von cc.ps1 start gefunden' -ErrorAction Continue
                exit 3
            }
            $ideId = [int] $Matches[1]
        }
        # Nie in eine schon laufende IDE bauen, etwa die des Benutzers.
        if ($before -contains $ideId) {
            Write-Error "pid $ideId gehört zu einer schon laufenden IDE; Abbruch, um sie nicht zu benutzen" -ErrorAction Continue
            $ideId = $null
            exit 3
        }
        Wait-ProjectsOpen $ideId @($projects.Values)

        $number = 0
        foreach ($case in $caseFiles) {
            $number++
            $targets = $(if ($case.Plattform) { @($case.Plattform) } else { $Platforms })
            foreach ($platform in $targets) {
                Write-Step "[$number/$($caseFiles.Count)] $($case.Stem) ($platform)"
                $build = Invoke-Cc @('build', '-Instance', "$ideId", '-Project', $projects[$case.Stem], '-Platform', $platform, '-NoSave', '-Json')
                $rows += Get-BuildRows $case $platform $build
            }
        }
    } catch {
        Write-Error $_ -ErrorAction Continue
        $exitCode = 3
    } finally {
        if ($null -ne $ideId) {
            Write-Step 'Scratch-IDE beenden'
            for ($attempt = 1; $attempt -le $QuitAttempts; $attempt++) {
                $quit = Invoke-Cc @('quit', '-Instance', "$ideId")
                if ($quit.ExitCode -eq 0) { break }
                Write-Host "IDE noch beschäftigt, Versuch $attempt von $QuitAttempts"
                Start-Sleep -Seconds $QuitDelaySeconds
            }
        }
    }

    Write-Result $rows
}

if ($AtlasServer) {
    if (-not (Test-Path $AtlasServer)) {
        Write-Error "Nicht gefunden: $AtlasServer" -ErrorAction Continue
        exit 3
    }
    Invoke-Atlas 'strict'
    Invoke-Atlas 'standard'
}
exit $exitCode
