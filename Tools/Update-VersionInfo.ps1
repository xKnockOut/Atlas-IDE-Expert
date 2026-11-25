<#
.SYNOPSIS
    Schreibt die Versionsressource (Dateiversion, Produktversion, Herausgeber) in alle ausgelieferten Projekte.

.DESCRIPTION
    Ausgeliefert werden die Packages (Packages/*/*.dproj) und die Programme (Application/*.dproj). Jedes
    bekommt in der Gruppe für alle Konfigurationen und Plattformen ('$(Base)'!='') dieselben Angaben:
    - VerInfo_MajorVer, VerInfo_MinorVer, VerInfo_Release, VerInfo_Build und FileVersion aus der Version
      in TAtlasVersion.cVersion nach der Regel unten,
    - ProductVersion numerisch wie FileVersion und der SemVer-Text (z. B. 2.3.0-rc.1) in Comments; die IDE
      schreibt ProductVersion als PRODUCTVERSION-Zahlen in die .vrc, „0-rc“ bricht den Ressourcen-Compiler ab,
    - CompanyName, ProductName, LegalCopyright und ProgramID des Projekts (statt der Vorgaben der IDE
      „com.embarcadero.…“ und „1.0.0.0“).
    VerInfo-Einträge in anderen Gruppen (die IDE legt sie nur für Win64x an) werden entfernt. Damit die
    Ressource in der BPL bzw. EXE landet, braucht die .dpk bzw. .dpr {$R *.res}; das Skript ergänzt es
    nach der ersten Zeile. Die .res erzeugt der Bau aus den Angaben der .dproj.

    Vierte Stelle (Build) der numerischen Version, damit Windows Vorabversionen vor der stabilen ordnet:
    - Vorabversion alpha.N: 1000 + N, beta.N: 2000 + N, rc.N: 3000 + N (N von 1 bis 999),
    - stabile Version: 9000.
    2.3.0-rc.1 ist also 2.3.0.3001, 2.3.0 ist 2.3.0.9000. Andere Vorabkennungen lehnt das Skript ab.

    Set-Version.ps1 ruft das Skript auf, Check-Version.ps1 ruft es mit -Check auf.

    Exit-Code 0: in Ordnung bzw. geschrieben, 1: Abweichung (mit -Check) oder ungültige Version.

.PARAMETER Version
    SemVer-Version; ohne Angabe die aus TAtlasVersion.cVersion.

.PARAMETER Check
    Nur prüfen, nichts schreiben.

.EXAMPLE
    pwsh Tools/Update-VersionInfo.ps1

.EXAMPLE
    pwsh Tools/Update-VersionInfo.ps1 -Check
#>
[CmdletBinding()]
param(
    [string] $Version = '',
    [switch] $Check,
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CompanyName = 'xKnockOut'
$ProductName = 'Atlas IDE Expert'
$Copyright = 'Copyright (c) xKnockOut, MIT License'
$ProgramIdPrefix = 'io.github.xknockout.atlas.'
$Stages = @{ 'alpha' = 1000; 'beta' = 2000; 'rc' = 3000 }
$StableBuild = 9000

function Get-NumericVersion([string] $SemVer) {
    if ($SemVer -notmatch '^(\d+)\.(\d+)\.(\d+)(?:-([a-z]+)\.(\d+))?$') {
        throw "'$SemVer' hat keine numerische Form (erlaubt: X.Y.Z, X.Y.Z-alpha.N, -beta.N, -rc.N)"
    }
    $Build = $StableBuild
    if ($Matches[4]) {
        $Number = [int] $Matches[5]
        if (-not $Stages.ContainsKey($Matches[4]) -or $Number -lt 1 -or $Number -gt 999) {
            throw "'$SemVer': Vorabkennung $($Matches[4]).$Number ist nicht alpha, beta oder rc mit 1 bis 999"
        }
        $Build = $Stages[$Matches[4]] + $Number
    }
    return [int[]] @([int] $Matches[1], [int] $Matches[2], [int] $Matches[3], $Build)
}

function Get-Block([string] $SemVer, [string] $Indent, [string] $NewLine) {
    $Parts = Get-NumericVersion $SemVer
    $FileVersion = $Parts -join '.'
    $Keys = "CompanyName=$CompanyName;FileDescription=$ProductName - `$(MSBuildProjectName);" +
        "FileVersion=$FileVersion;InternalName=`$(MSBuildProjectName);LegalCopyright=$Copyright;" +
        "LegalTrademarks=;OriginalFilename=;ProgramID=$ProgramIdPrefix`$(MSBuildProjectName);" +
        "ProductName=$ProductName;ProductVersion=$FileVersion;Comments=$SemVer"
    $Lines = @(
        "<VerInfo_IncludeVerInfo>true</VerInfo_IncludeVerInfo>",
        "<VerInfo_MajorVer>$($Parts[0])</VerInfo_MajorVer>",
        "<VerInfo_MinorVer>$($Parts[1])</VerInfo_MinorVer>",
        "<VerInfo_Release>$($Parts[2])</VerInfo_Release>",
        "<VerInfo_Build>$($Parts[3])</VerInfo_Build>",
        "<VerInfo_Locale>1033</VerInfo_Locale>",
        "<VerInfo_Keys>$Keys</VerInfo_Keys>"
    )
    return ($Lines | ForEach-Object { "$Indent$_$NewLine" }) -join ''
}

function Get-UpdatedProject([string] $Text, [string] $SemVer) {
    $NewLine = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $Text = [regex]::Replace($Text, '(?m)^[ \t]*<VerInfo_\w+>[^\r\n]*</VerInfo_\w+>\r?\n', '')
    $Group = [regex]::Match($Text, "(?s)(<PropertyGroup Condition=""'\`$\(Base\)'!=''"">\r?\n)(.*?)([ \t]*)</PropertyGroup>")
    if (-not $Group.Success) { throw "Gruppe '`$(Base)'!='' fehlt" }
    $Indent = $Group.Groups[3].Value + '    '
    $Insert = $Group.Groups[2].Index + $Group.Groups[2].Length
    return $Text.Substring(0, $Insert) + (Get-Block $SemVer $Indent $NewLine) + $Text.Substring($Insert)
}

function Get-UpdatedSource([string] $Text) {
    if ($Text -match '(?mi)^\{\$R \*\.res\}') { return $Text }
    $NewLine = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $First = $Text.IndexOf($NewLine)
    return $Text.Substring(0, $First + $NewLine.Length) + $NewLine + '{$R *.res}' + $Text.Substring($First + $NewLine.Length)
}

if ($Version -eq '') {
    $Unit = Join-Path $Root 'Packages/Atlas.Text/Source/Product/Atlas.Text.Product.Version.pas'
    $Version = [regex]::Match([IO.File]::ReadAllText($Unit), "Version\s*=\s*'([^']+)'").Groups[1].Value
}
try {
    $null = Get-NumericVersion $Version
} catch {
    Write-Host "Fehler: $($_.Exception.Message)"
    exit 1
}

# Schreibt AText mit derselben Kodierung (UTF-8 mit oder ohne BOM) wie die Datei bisher.
function Write-Like([string] $Path, [string] $Text) {
    $Bytes = [IO.File]::ReadAllBytes($Path)
    $Bom = $Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF
    [IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($Bom)))
}

$Projects = @(Get-ChildItem -Path (Join-Path $Root 'Packages') -Filter '*.dproj' -Recurse -File) +
    @(Get-ChildItem -Path (Join-Path $Root 'Application') -Filter '*.dproj' -File)
$Errors = @()
foreach ($Project in $Projects | Sort-Object FullName) {
    $Relative = [IO.Path]::GetRelativePath($Root, $Project.FullName)
    $Text = [IO.File]::ReadAllText($Project.FullName)
    $Main = [regex]::Match($Text, '<MainSource>([^<]+)</MainSource>').Groups[1].Value
    $SourcePath = Join-Path $Project.DirectoryName $Main
    $Source = [IO.File]::ReadAllText($SourcePath)
    try {
        $NewText = Get-UpdatedProject $Text $Version
    } catch {
        $Errors += "${Relative}: $($_.Exception.Message)"
        continue
    }
    $NewSource = Get-UpdatedSource $Source
    if ($Check) {
        if ($NewText -ne $Text) { $Errors += "${Relative}: Versionsangaben weichen von $Version ab" }
        if ($NewSource -ne $Source) { $Errors += "${Relative}: {`$R *.res} fehlt in $Main" }
        continue
    }
    if ($NewText -ne $Text) { Write-Like $Project.FullName $NewText }
    if ($NewSource -ne $Source) { Write-Like $SourcePath $NewSource }
}

if ($Errors.Count -gt 0) {
    $Errors | ForEach-Object { Write-Host "Fehler: $_" }
    Write-Host 'Beheben: pwsh Tools/Update-VersionInfo.ps1'
    exit 1
}
if ($Check) {
    Write-Host "Versionsressource $Version in $($Projects.Count) Projekten in Ordnung."
} else {
    Write-Host "Versionsressource $Version in $($Projects.Count) Projekten geschrieben."
}
exit 0
