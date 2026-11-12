<#
.SYNOPSIS
    Prüft New-ReleasePackage.ps1 und New-VersionFile.ps1 (#1519): Aufbau des
    Release-Pakets, Abbruch bei fehlenden oder veralteten Builds und die
    Versionsdatei mit und ohne Paket.

.DESCRIPTION
    Legt in einem temporären Ordner Platzhalter für die Release-Builds an
    (Server, Updater, BPL und Map je Plugin-Package und Plattform), packt sie
    und prüft die Einträge des ZIP. Danach baut je Fall einen Fehler ein und
    erwartet den Abbruch mit passender Meldung. Die HTML-Doku bleibt außen vor
    (-NoDocs), weil Build-Docs nicht auf jedem Rechner läuft.

.EXAMPLE
    pwsh Tools/Test-ReleasePackage.ps1
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression.FileSystem
$Pack = Join-Path $PSScriptRoot 'New-ReleasePackage.ps1'
$VersionScript = Join-Path $PSScriptRoot 'New-VersionFile.ps1'
$Failures = [System.Collections.Generic.List[string]]::new()

if (((& (Join-Path $PSScriptRoot 'Check-Version.ps1') -Root $Root 6>&1) -join "`n") -notmatch 'Version (\S+) in Ordnung') {
    throw 'Version des Quelltexts nicht ermittelt'
}
$Version = $Matches[1]
$Packages = @(Get-ChildItem (Join-Path $Root 'Packages') -Directory -Filter 'Atlas.IDE.*' |
    Where-Object { Test-Path (Join-Path $_.FullName "$($_.Name).dpk") } | ForEach-Object Name)

function New-Builds([string] $Output) {
    $Bin = Join-Path $Output 'Win64/Release/Bin'
    New-Item -ItemType Directory -Force $Bin | Out-Null
    foreach ($Name in 'AtlasServer.exe', 'AtlasServer.map', 'AtlasUpdate.exe', 'AtlasMonitor.exe', 'WebView2Loader.dll') {
        Set-Content -LiteralPath (Join-Path $Bin $Name) -Value $Name
    }
    foreach ($Platform in 'Win32', 'Win64') {
        $Bpl = Join-Path $Output "$Platform/Release/Bpl"
        New-Item -ItemType Directory -Force $Bpl | Out-Null
        foreach ($Name in $Packages) {
            Set-Content -LiteralPath (Join-Path $Bpl "${Name}370.bpl") -Value "$Name $Platform"
            Set-Content -LiteralPath (Join-Path $Bpl "${Name}370.map") -Value "$Name map"
        }
    }
}

function Expect-Failure([string] $Case, [string] $Pattern, [scriptblock] $Break, [string] $PackVersion = $Version) {
    $Output = Join-Path ([IO.Path]::GetTempPath()) ('atlas-package-' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Builds $Output
        & $Break $Output
        try {
            & $Pack -Version $PackVersion -Root $Root -Output $Output -OutFile (Join-Path $Output 'p.zip') -NoDocs 6>$null
            $Failures.Add("${Case}: kein Abbruch")
        } catch {
            if ($_.Exception.Message -notmatch $Pattern) {
                $Failures.Add("${Case}: falsche Meldung: $($_.Exception.Message)")
            }
        }
    } finally {
        Remove-Item $Output -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Vollständige Builds: Paket mit Server, Updater, Daten und je Plattform BPL und Map jedes Packages.
$Output = Join-Path ([IO.Path]::GetTempPath()) ('atlas-package-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Builds $Output
    $Zip = Join-Path $Output "atlas-ide-expert-$Version.zip"
    & $Pack -Version $Version -Root $Root -Output $Output -OutFile $Zip -NoDocs 6>$null
    $Archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $Entries = @($Archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    } finally {
        $Archive.Dispose()
    }
    $Expected = @('AtlasServer.exe', 'AtlasServer.map', 'AtlasUpdate.exe', 'AtlasMonitor.exe', 'WebView2Loader.dll',
        'LICENSE', 'whatsnew.json', 'tips.json')
    foreach ($Platform in 'Win32', 'Win64') {
        foreach ($Name in $Packages) {
            $Expected += "$Platform/${Name}370.bpl", "$Platform/${Name}370.map"
        }
    }
    foreach ($Entry in $Expected) {
        if ($Entry -notin $Entries) {
            $Failures.Add("Paket: $Entry fehlt")
        }
    }
    foreach ($Folder in 'Profile/', 'Vorlagen/', 'Beispiele/', 'Tipps/') {
        if (-not ($Entries | Where-Object { $_.StartsWith($Folder) })) {
            $Failures.Add("Paket: Ordner $Folder fehlt")
        }
    }

    # Versionsdatei mit Paket: URL und SHA-256 je Datei.
    $Source = Join-Path $Output "atlas-ide-expert-source-$Version.zip"
    Set-Content -LiteralPath $Source -Value 'Quelltext'
    $Json = Join-Path $Output 'atlas-version.json'
    & $VersionScript -Version $Version -Repository 'o/r' -SourceZip $Source -PackageZip $Zip -OutFile $Json | Out-Null
    $Manifest = Get-Content -Raw $Json | ConvertFrom-Json
    $Package = $Manifest.packages.'37.0'
    if ($Manifest.version -ne $Version -or $Manifest.changes -ne "https://github.com/o/r/releases/tag/v$Version") {
        $Failures.Add('Versionsdatei: Version oder Änderungen falsch')
    }
    if ($Package.url -ne "https://github.com/o/r/releases/download/v$Version/atlas-ide-expert-$Version.zip" -or
        $Package.sha256 -ne (Get-FileHash $Zip -Algorithm SHA256).Hash.ToLowerInvariant()) {
        $Failures.Add('Versionsdatei: Paket falsch')
    }
    if ($Manifest.source.sha256 -notmatch '^[0-9a-f]{64}$') {
        $Failures.Add('Versionsdatei: SHA-256 des Quelltexts falsch')
    }
    # Ohne Paket: kein "packages", Quelltext bleibt.
    & $VersionScript -Version $Version -Repository 'o/r' -SourceZip $Source -OutFile $Json | Out-Null
    $Manifest = Get-Content -Raw $Json | ConvertFrom-Json
    if ($Manifest.PSObject.Properties.Name -contains 'packages' -or -not $Manifest.source) {
        $Failures.Add('Versionsdatei ohne Paket: "packages" vorhanden oder Quelltext fehlt')
    }
} finally {
    Remove-Item $Output -Recurse -Force -ErrorAction SilentlyContinue
}

$Last = $Packages[-1]
Expect-Failure 'Updater fehlt' 'AtlasUpdate\.exe' { param($O) Remove-Item (Join-Path $O 'Win64/Release/Bin/AtlasUpdate.exe') }
Expect-Failure 'Monitor fehlt' 'AtlasMonitor\.exe' { param($O) Remove-Item (Join-Path $O 'Win64/Release/Bin/AtlasMonitor.exe') }
Expect-Failure 'WebView2-Lader fehlt' 'WebView2Loader\.dll' { param($O) Remove-Item (Join-Path $O 'Win64/Release/Bin/WebView2Loader.dll') }
Expect-Failure 'Win64-BPL fehlt' "Win64-BPL von $([regex]::Escape($Last))" {
    param($O) Remove-Item (Join-Path $O "Win64/Release/Bpl/${Last}370.bpl")
}
Expect-Failure 'Map fehlt' "$([regex]::Escape($Last))370.map" { param($O) Remove-Item (Join-Path $O "Win32/Release/Bpl/${Last}370.map") }
if (Test-Path (Join-Path $Root '.git')) {
    Expect-Failure 'Veralteter Build' 'Älter als der letzte Commit' {
        param($O) (Get-Item (Join-Path $O 'Win64/Release/Bin/AtlasServer.exe')).LastWriteTimeUtc = [datetime]'2000-01-01'
    }
}
Expect-Failure 'Falsche Version' 'Version im Quelltext ist nicht' { param($O) } '0.0.1'

if ($Failures.Count -gt 0) {
    $Failures | ForEach-Object { Write-Host "FEHLER: $_" }
    exit 1
}
Write-Host "Release-Paket und Versionsdatei in Ordnung ($($Packages.Count) Packages)."
# Gerufene Prüfskripte hinterlassen in den Fehlerfällen $LASTEXITCODE 1; der Selbsttest selbst ist bestanden.
exit 0
