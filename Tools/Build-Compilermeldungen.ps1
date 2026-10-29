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
      // Schalter: --doc      zusätzliche Option für dcc (DCC_AdditionalSwitches)

    Ablauf wie Tools/Build-DccFaelle.ps1: eigene Scratch-IDE über cc.ps1 starten (pid darf zu keiner schon
    laufenden IDE gehören), jedes Projekt mit "build" übersetzen, die dcc-Zeilen aus dem logFile übernehmen,
    am Ende "quit".

    Ergebnis: Output/Compilermeldungen/dcc.tsv mit den Spalten Fall, Plattform, Ok, Datei, Zeile, Code, Art, Text.
    Ein Fall ohne dcc-Meldung steht mit leerem Code in der Tabelle.

    Mit -AtlasServer prüft das Skript danach Tests/Compilermeldungen mit "AtlasServer --check" (Profile strict
    und standard) und legt die JSON-Ergebnisse daneben ab. Tools/Compare-Compilermeldungen.py vergleicht beides.

    Exit-Code 0: alle Projekte gebaut (mit oder ohne Meldungen). 3: Aufruf- oder Umgebungsfehler.

.EXAMPLE
    pwsh Tools/Build-Compilermeldungen.ps1
    pwsh Tools/Build-Compilermeldungen.ps1 -Platforms Win32 -Cases 'Cm.W1*'
    pwsh Tools/Build-Compilermeldungen.ps1 -AtlasServer Output\Win64\Debug\Bin\AtlasServer.exe
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [string] $CcScript = $(if ($env:CC_SCRIPT) { $env:CC_SCRIPT } else { 'C:\Projekte\IDE-Plugins\Claude-Compile\cc.ps1' }),
    [string[]] $Platforms = @('Win32', 'Win64'),
    # Dateimuster der Fälle (ohne Endung), etwa 'Cm.W1*' oder 'CmE2200'.
    [string[]] $Cases = @('*'),
    # Zusätzliche Argumente für "cc.ps1 start", etwa ein eigenes Registry-Profil der IDE.
    [string[]] $CcStartArguments = @(),
    [string] $AtlasServer = '',
    [switch] $SkipBuild,
    [int] $QuitAttempts = 10,
    [int] $QuitDelaySeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TestDir = Join-Path $Root 'Tests/Compilermeldungen'
$CaseDir = Join-Path $TestDir 'Faelle'
$OutDir = Join-Path $Root 'Output/Compilermeldungen'
$ProjectDir = Join-Path $OutDir 'Projekte'
$ResultFile = Join-Path $OutDir 'dcc.tsv'
# "[dcc32 Fehler] Cm.E2003.pas(12): E2003 Undeklarierter Bezeichner: 'X'"
$DccPattern = '\[dcc\w*\s+([^\]]+)\]\s*(?:([^\s(][^(]*)\((\d+)\))?:?\s*(?:([EWHFX]\d{4})\s+)?(.*)$'
$CasePattern = '^Cm\.?[EWHF]\d{4}'

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
            if ($i + 1 -lt $Arguments.Count -and $Arguments[$i + 1] -notmatch '^-\w+$') {
                $named[$Matches[1]] = $Arguments[$i + 1]
                $i++
            } else {
                $named[$Matches[1]] = $true
            }
        } else {
            $positional += $arg
        }
    }
    # StrictMode dieses Skripts nicht an cc.ps1 vererben (liest optionale Felder aus status.json).
    $output = & { Set-StrictMode -Off; & $CcScript @positional @named } *>&1 | Out-String
    [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE }
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
if (-not $SkipBuild) {
    if (-not (Test-Path $CcScript)) {
        Write-Error "Nicht gefunden: $CcScript" -ErrorAction Continue
        exit 3
    }
    Write-Step "$($caseFiles.Count) Fälle, Projekte erzeugen"
    $projects = @{}
    foreach ($case in $caseFiles) {
        $projects[$case.Stem] = New-CaseProject $case
    }

    $rows = @()
    $ideId = $null
    $before = Get-IdeProcessIds
    try {
        Write-Step 'Scratch-IDE starten'
        $first = $projects[$caseFiles[0].Stem]
        $start = Invoke-Cc (@('start', '-Project', $first) + $CcStartArguments)
        Write-Host $start.Output
        if ($start.Output -notmatch 'pid\D*(\d+)') {
            Write-Error 'pid der Scratch-IDE nicht in der Ausgabe von cc.ps1 start gefunden' -ErrorAction Continue
            exit 3
        }
        $ideId = [int] $Matches[1]
        # Nie in eine schon laufende IDE bauen, etwa die des Benutzers.
        if ($before -contains $ideId) {
            Write-Error "pid $ideId gehört zu einer schon laufenden IDE; Abbruch, um sie nicht zu benutzen" -ErrorAction Continue
            $ideId = $null
            exit 3
        }

        $number = 0
        foreach ($case in $caseFiles) {
            $number++
            $targets = $(if ($case.Plattform) { @($case.Plattform) } else { $Platforms })
            foreach ($platform in $targets) {
                Write-Step "[$number/$($caseFiles.Count)] $($case.Stem) ($platform)"
                $build = Invoke-Cc @('build', '-Instance', "$ideId", '-Project', $projects[$case.Stem], '-Platform', $platform, '-Json')
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

    $header = "Fall`tPlattform`tOk`tDatei`tZeile`tCode`tArt`tText"
    $lines = @($header) + @($rows | ForEach-Object {
        @($_.Fall, $_.Plattform, $_.Ok, $_.Datei, $_.Zeile, $_.Code, $_.Art, ($_.Text -replace "`t", ' ')) -join "`t"
    })
    Set-Content -Path $ResultFile -Value $lines -Encoding UTF8
    Write-Step "dcc-Ergebnis in $ResultFile ($($rows.Count) Zeilen)"
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
