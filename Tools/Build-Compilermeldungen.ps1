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

    Ablauf wie Tools/Build-DccFaelle.ps1: jedes Projekt einzeln mit Tools/Build-Ide.ps1 -Mode build -Json
    übersetzen (eigene Bau-IDE im Registry-Profil -IdeProfile, Vorgabe AtlasBuild, mit fester Plugin-Kopie aus
    "Build-Ide.ps1 -Setup"; eine schon laufende IDE bleibt unberührt) und die Meldungen aus steps[].messages
    übernehmen. Jeder Lauf startet eine eigene Bau-IDE; für viele Fälle ist -Dcc deutlich schneller.

    Listen aus "pwsh -File" ('a','b' kommt als "a,b" an) teilt das Skript an Kommas; aus PowerShell heraus
    besser "pwsh -Command { & ./Tools/Build-Compilermeldungen.ps1 ... }".

    Ergebnis: Output/Compilermeldungen/dcc.tsv mit den Spalten Fall, Plattform, Ok, Datei, Zeile, Code, Art, Text.
    Ein Fall ohne dcc-Meldung steht mit leerem Code in der Tabelle.

    Mit -Dcc übersetzt das Skript ohne IDE mit den Kommandozeilen-Compilern dcc32.exe und dcc64.exe der mit
    -BdsVersion gewählten Delphi-Version (Vorgabe 37.0 = Delphi 13, 23.0 = Delphi 12); dann braucht es weder eine
    Bau-IDE noch ein Registry-Profil. Die Starter-Edition hat keine Kommandozeilen-Compiler. -ResultFile legt die Tabelle
    an anderer Stelle ab, etwa für einen Lauf mit Delphi 12 neben dem mit Delphi 13 (#1383).

    Mit -AtlasServer prüft das Skript danach Tests/Compilermeldungen mit "AtlasServer --check" (Profile strict
    und standard) und legt die JSON-Ergebnisse daneben ab. Tools/Compare-Compilermeldungen.py vergleicht beides.

    Exit-Code 0: alle Projekte gebaut (mit oder ohne Meldungen). 3: Aufruf- oder Umgebungsfehler.

.EXAMPLE
    pwsh Tools/Build-Compilermeldungen.ps1
    pwsh Tools/Build-Compilermeldungen.ps1 -Platforms Win32 -Cases 'Cm.W1*'
    pwsh Tools/Build-Compilermeldungen.ps1 -AtlasServer Output\Win64\Debug\Bin\AtlasServer.exe
    pwsh Tools/Build-Compilermeldungen.ps1 -Dcc -BdsVersion 23.0 -ResultFile Output\Compilermeldungen\dcc-delphi12.tsv
    pwsh Tools/Build-Compilermeldungen.ps1 -BdsVersion 23.0 -IdeProfile AtlasBuild12 -ResultFile Output\Compilermeldungen\dcc-delphi12.tsv
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [string[]] $Platforms = @('Win32', 'Win64'),
    # Dateimuster der Fälle (ohne Endung), etwa 'Cm.W1*' oder 'CmE2200'.
    [string[]] $Cases = @('*'),
    # Registry-Profil der Bau-IDE (bds -r <Profil>) für Tools/Build-Ide.ps1; leer = dessen Vorgabe AtlasBuild.
    [string] $IdeProfile = '',
    # Delphi-Version als BDS-Nummer: 37.0 = Delphi 13, 23.0 = Delphi 12 (Registry-Pfad der IDE und der Compiler).
    [string] $BdsVersion = '37.0',
    # Ohne IDE mit dcc32.exe/dcc64.exe übersetzen (nicht in der Starter-Edition).
    [switch] $Dcc,
    # Ergebnistabelle; leer = Output/Compilermeldungen/dcc.tsv.
    [string] $ResultFile = '',
    [string] $AtlasServer = '',
    [switch] $SkipBuild
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
# Kommandozeile: "Cm.W1036.pas(14) Warnung: W1036 ..." bzw. "Fatal: F2613 ..." ohne Datei.
$DccConsolePattern = '^(?:(.+?)\((\d+)\)\s+)?([^:()]+?):\s+([EWHFX]\d{4})\s+(.*)$'
# Ausgabe von dcc32/dcc64 der Community Edition, die nicht auf der Kommandozeile übersetzt (Exit-Code 0).
$DccUnsupportedPattern = 'does not support command line compiling'
$CasePattern = '^Cm\.?[EWHF]\d{4}'
# XML-Warnungen W1201-W1208 (DCC_XML_* in der .dproj, -W+XML_* auf der Kommandozeile).
$XmlWarnings = @('WHITESPACE_NOT_ALLOWED', 'UNKNOWN_ENTITY', 'INVALID_NAME_START', 'INVALID_NAME', 'EXPECTED_CHARACTER',
    'CREF_NO_RESOLVE', 'NO_PARM', 'NO_MATCHING_PARM')

function Write-Step([string] $Text) {
    Write-Host "== $Text"
}

# Übersetzt ein Projekt über Tools/Build-Ide.ps1; liefert dessen JSON-Antwort und die rohe Ausgabe.
function Invoke-IdeBuild([string] $Project, [string] $Platform) {
    $arguments = @{ Project = $Project; Platform = $Platform; Mode = 'build'; Version = $BdsVersion; Json = $true }
    if ($IdeProfile) { $arguments['Profile'] = $IdeProfile }
    $script = Join-Path $PSScriptRoot 'Build-Ide.ps1'
    $output = & { Set-StrictMode -Off; & $script @arguments } *>&1 | Out-String
    $result = $null
    $start = $output.IndexOf('{')
    if ($start -ge 0) {
        try { $result = $output.Substring($start) | ConvertFrom-Json } catch { $result = $null }
    }
    [pscustomobject]@{ Output = $output; Result = $result }
}

function Get-BdsRoot {
    (Get-ItemProperty -Path "HKCU:\Software\Embarcadero\BDS\$BdsVersion" -Name RootDir).RootDir
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
    $result = $Build.Result
    $ok = Get-Property $result 'ok'
    $rows = @()
    foreach ($step in @(Get-Property $result 'steps')) {
        if ($null -eq $step) { continue }
        foreach ($message in @(Get-Property $step 'messages')) {
            if ($null -eq $message) { continue }
            $file = $(if ($message.file) { Split-Path -Leaf ([string] $message.file) } else { '' })
            $rows += [pscustomobject]@{
                Fall = $Case.Stem; Plattform = $Platform; Ok = "$ok"; Datei = $file; Zeile = "$($message.line)"
                Code = "$($message.code)"; Art = "$($message.severity)"; Text = "$($message.text)".Trim()
            }
        }
    }
    if ($rows.Count -eq 0) {
        # Ohne lesbare Meldungen die rohe Ausgabe des Bau-Skripts mitgeben.
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
    if (($output -join ' ') -match $DccUnsupportedPattern) {
        throw "$exe übersetzt nicht auf der Kommandozeile (Community Edition)"
    }
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
        # Community Edition (#1383): dcc32 meldet nur, dass es nicht auf der Kommandozeile übersetzt, und endet
        # mit 0; ohne diese Prüfung stünde jeder Fall als übersetzt ohne Meldung in der Tabelle.
        $probe = @(& $path 2>&1 | ForEach-Object { "$_" }) -join ' '
        if ($probe -match $DccUnsupportedPattern) {
            Write-Error "$path übersetzt nicht auf der Kommandozeile (Community Edition): $probe" -ErrorAction Continue
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
    Write-Step "$($caseFiles.Count) Fälle, Projekte erzeugen"
    $projects = @{}
    foreach ($case in $caseFiles) {
        $projects[$case.Stem] = New-CaseProject $case
    }
    $rows = @()
    try {
        $number = 0
        foreach ($case in $caseFiles) {
            $number++
            $targets = $(if ($case.Plattform) { @($case.Plattform) } else { $Platforms })
            foreach ($platform in $targets) {
                Write-Step "[$number/$($caseFiles.Count)] $($case.Stem) ($platform)"
                $rows += Get-BuildRows $case $platform (Invoke-IdeBuild $projects[$case.Stem] $platform)
            }
        }
    } catch {
        Write-Error $_ -ErrorAction Continue
        $exitCode = 3
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
