<#
.SYNOPSIS
    Prüft, dass jedes Projekt im Debug-Build mit Bereichs- und Überlaufprüfung übersetzt.

.DESCRIPTION
    Bereichs- und Überlaufprüfung ({$R+}, {$Q+}) findet Fehler an der Stelle, an der sie
    entstehen, statt Speicher still zu überschreiben. Server, Atlas.Common und die Tests
    hatten sie schon im Debug-Build; das Plugin und die Anwendungen bekommen sie ebenso.
    Damit ein neues Projekt sie nicht vergisst, gilt für jede .dproj:

    - Es gibt eine Konfiguration Debug.
    - Ihr Abschnitt ('$(Cfg_N)'!='') setzt DCC_RangeChecking und DCC_IntegerOverflowCheck
      auf true.
    - Kein Abschnitt der Debug-Konfiguration, auch nicht je Plattform (Cfg_N_Win64), schaltet
      eine der beiden wieder aus. Die Basis (Base, Base_Win64) steht in der .dproj davor und
      wird vom Debug-Abschnitt überschrieben.

    Ausgenommen sind Projekte, die Atlas selbst als Eingabe dienen (Fälle für dcc-Meldungen,
    Referenzprojekt): Dort sind die Schalter Teil des Prüflings.

    Gewollte Überläufe (Hashes, Prüfsummen) stehen im Quelltext in einer Insel:
      {$IFOPT Q+}{$DEFINE ATLAS_HASH_UEBERLAUF}{$Q-}{$ENDIF}
      ...
      {$IFDEF ATLAS_HASH_UEBERLAUF}{$Q+}{$UNDEF ATLAS_HASH_UEBERLAUF}{$ENDIF}

    Exit-Code 0: keine Verstöße, 1: mindestens ein Verstoß.

.EXAMPLE
    pwsh Tools/Check-RuntimeChecks.ps1

.EXAMPLE
    pwsh Tools/Check-RuntimeChecks.ps1 -SelfTest
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [switch] $SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ordner (relativ zum Stamm, mit /) mit Projekten, die Atlas als Prüfling dienen.
$Exempt = @(
    'Tests/DccFaelle/',
    'Tests/Compilermeldungen/',
    'Tests/Referenzprojekt/'
)
$Switches = @('DCC_RangeChecking', 'DCC_IntegerOverflowCheck')

function Get-Violations([string] $Text) {
    $Found = [System.Collections.Generic.List[string]]::new()
    $Xml = [xml]::new()
    try {
        $Xml.LoadXml($Text)
    } catch {
        $Found.Add("kein gültiges XML: $($_.Exception.Message)")
        return $Found
    }
    $Groups = @($Xml.GetElementsByTagName('PropertyGroup'))
    $DebugKey = $null
    foreach ($Group in $Groups) {
        $Condition = $Group.GetAttribute('Condition')
        if ($Condition -match "'\`$\(Config\)'=='Debug'.*'\`$\((Cfg_\d+)\)'!=''") {
            $DebugKey = $Matches[1]
        }
    }
    if ($null -eq $DebugKey) {
        $Found.Add('keine Konfiguration Debug')
        return $Found
    }
    $Own = $null
    foreach ($Group in $Groups) {
        $Condition = $Group.GetAttribute('Condition')
        $IsOwn = $Condition -eq "'`$($DebugKey)'!=''"
        $IsDebug = $IsOwn -or $Condition -match "^'\`$\($DebugKey(_\w+)?\)'!=''$"
        if ($IsOwn) {
            $Own = $Group
        }
        if (-not $IsDebug) {
            continue
        }
        foreach ($Switch in $Switches) {
            foreach ($Node in @($Group.ChildNodes | Where-Object { $_.LocalName -eq $Switch })) {
                if ($Node.InnerText.Trim() -ne 'true') {
                    $Found.Add("$Switch = $($Node.InnerText.Trim()) in $Condition")
                }
            }
        }
    }
    if ($null -eq $Own) {
        $Found.Add("kein Abschnitt '`$($DebugKey)'!='' für Debug")
        return $Found
    }
    foreach ($Switch in $Switches) {
        $Nodes = @($Own.ChildNodes | Where-Object { $_.LocalName -eq $Switch })
        if ($Nodes.Count -eq 0 -or $Nodes[-1].InnerText.Trim() -ne 'true') {
            $Found.Add("Debug ohne <$Switch>true</$Switch>")
        }
    }
    $Found
}

function New-Project([string] $Debug, [string] $Extra = '') {
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    "<PropertyGroup Condition=`"'`$(Config)'=='Base' or '`$(Base)'!=''`"><Base>true</Base></PropertyGroup>" +
    "<PropertyGroup Condition=`"'`$(Config)'=='Debug' or '`$(Cfg_1)'!=''`"><Cfg_1>true</Cfg_1></PropertyGroup>" +
    "<PropertyGroup Condition=`"'`$(Config)'=='Release' or '`$(Cfg_2)'!=''`"><Cfg_2>true</Cfg_2></PropertyGroup>" +
    "<PropertyGroup Condition=`"'`$(Cfg_1)'!=''`">$Debug</PropertyGroup>" +
    "<PropertyGroup Condition=`"'`$(Cfg_2)'!=''`"><DCC_DebugInformation>0</DCC_DebugInformation></PropertyGroup>" +
    $Extra + '</Project>'
}

if ($SelfTest) {
    $Both = '<DCC_RangeChecking>true</DCC_RangeChecking><DCC_IntegerOverflowCheck>true</DCC_IntegerOverflowCheck>'
    $Cases = @(
        @{ Name = 'beide an'; Text = (New-Project $Both); Count = 0 },
        @{ Name = 'keine'; Text = (New-Project ''); Count = 2 },
        @{ Name = 'nur R'; Text = (New-Project '<DCC_RangeChecking>true</DCC_RangeChecking>'); Count = 1 },
        @{ Name = 'Q aus'; Text = (New-Project '<DCC_RangeChecking>true</DCC_RangeChecking><DCC_IntegerOverflowCheck>false</DCC_IntegerOverflowCheck>'); Count = 2 },
        @{ Name = 'Debug Win64 aus'; Text = (New-Project $Both "<PropertyGroup Condition=`"'`$(Cfg_1_Win64)'!=''`"><DCC_RangeChecking>false</DCC_RangeChecking></PropertyGroup>"); Count = 1 },
        @{ Name = 'Base Win32 aus'; Text = (New-Project $Both "<PropertyGroup Condition=`"'`$(Base_Win32)'!=''`"><DCC_IntegerOverflowCheck>false</DCC_IntegerOverflowCheck></PropertyGroup>"); Count = 0 },
        @{ Name = 'Release aus'; Text = (New-Project $Both "<PropertyGroup Condition=`"'`$(Cfg_2_Win64)'!=''`"><DCC_RangeChecking>false</DCC_RangeChecking></PropertyGroup>"); Count = 0 },
        @{ Name = 'ohne Debug'; Text = '<Project><PropertyGroup><Config>Base</Config></PropertyGroup></Project>'; Count = 1 },
        @{ Name = 'kein XML'; Text = '<Project><PropertyGroup>'; Count = 1 }
    )
    $Failed = 0
    foreach ($Case in $Cases) {
        $Got = @(Get-Violations $Case.Text)
        if ($Got.Count -ne $Case.Count) {
            Write-Host "FEHLER: $($Case.Name): $($Got.Count) statt $($Case.Count) Verstöße ($($Got -join '; '))"
            $Failed++
        }
    }
    if ($Failed -gt 0) {
        exit 1
    }
    Write-Host 'Selbsttest der Prüfung auf Bereichs- und Überlaufprüfung bestanden.' -ForegroundColor Green
    exit 0
}

$Violations = [System.Collections.Generic.List[string]]::new()
$Files = @(Get-ChildItem -Path $Root -Recurse -File -Filter '*.dproj' |
    Where-Object { $_.FullName -notmatch '[\\/](\.git|Output|__history)[\\/]' })
$Checked = 0
foreach ($File in $Files) {
    $Relative = [IO.Path]::GetRelativePath($Root, $File.FullName).Replace('\', '/')
    if (@($Exempt | Where-Object { $Relative.StartsWith($_) }).Count -gt 0) {
        continue
    }
    $Checked++
    foreach ($Violation in @(Get-Violations ([IO.File]::ReadAllText($File.FullName)))) {
        $Violations.Add("${Relative}: $Violation")
    }
}

if ($Violations.Count -gt 0) {
    Write-Host 'Projekte ohne Bereichs- und Überlaufprüfung im Debug-Build:' -ForegroundColor Red
    $Violations | ForEach-Object { Write-Host "  $_" }
    Write-Host 'Im Abschnitt der Debug-Konfiguration ergänzen:' -ForegroundColor Red
    Write-Host '  <DCC_RangeChecking>true</DCC_RangeChecking>'
    Write-Host '  <DCC_IntegerOverflowCheck>true</DCC_IntegerOverflowCheck>'
    exit 1
}
Write-Host "$Checked Projekte mit Bereichs- und Überlaufprüfung im Debug-Build." -ForegroundColor Green
exit 0
