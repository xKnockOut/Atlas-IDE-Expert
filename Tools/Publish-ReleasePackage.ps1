<#
.SYNOPSIS
    Hängt ein lokal gebautes Release-Paket an ein bestehendes GitHub Release
    und trägt es in die Versionsdateien ein (#1519, ohne Delphi-Runner).

.DESCRIPTION
    Ohne Delphi-Runner legt der Release-Workflow das Release nur mit Notizen,
    Quelltext und einer Versionsdatei ohne Paket an. Das Plugin meldet die
    Version dann, der Update-Installer braucht aber ein Paket. Dieses Skript
    schließt die Lücke, nachdem der Workflow zum Tag gelaufen ist:

    1. Packt das Release-Paket aus den lokalen Release-Builds
       (New-ReleasePackage.ps1), außer -Package nennt ein fertiges.
    2. Lädt den Quelltext-ZIP des Releases und schreibt atlas-version.json mit
       Paket und Quelltext, je mit SHA-256 (New-VersionFile.ps1), und signiert
       sie mit dem eigenen Schlüssel für Updates (Sign-VersionFile.ps1).
    3. Lädt Paket, AtlasServer.exe/.map, atlas-version.json und
       atlas-version.json.sig in das Release (ersetzt vorhandene).
    4. Ersetzt atlas-version-beta.json samt Signatur im Vorab-Kanal
       „update-channel“, wenn der Kanal auf diese Version zeigt (sonst gibt es
       schon eine neuere).
    5. Ist AtlasUpdate.exe im Paket nicht Authenticode-signiert, schreibt es
       die Release-Notizen mit dem Hinweis auf unsignierte Binärdateien neu.

    Braucht die GitHub-CLI (gh), angemeldet mit Schreibrecht auf das Repository,
    und den privaten Schlüssel für die Versionsdatei (-SigningKey oder
    ATLAS_UPDATE_SIGNING_KEY): Die neu geschriebene Versionsdatei passte sonst
    nicht mehr zur Signatur des Workflows, und AtlasUpdate lehnte jedes Update ab.
    Das Code-Signing-Zertifikat für EXE und BPLs bleibt freiwillig.

.EXAMPLE
    pwsh Tools/Publish-ReleasePackage.ps1 -Version 2.0.0-beta.1 -SigningKey $HOME\Atlas-Schluessel\update-haupt.pem

.EXAMPLE
    pwsh Tools/Publish-ReleasePackage.ps1 -Version 2.0.0-beta.1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $Version,
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [string] $Repository = 'xKnockOut/Atlas-IDE-Expert',
    [string] $Package = '',
    [string] $Ide = '37.0',
    # Privater Schlüssel (PEM) für die Versionsdatei; sonst ATLAS_UPDATE_SIGNING_KEY.
    [string] $SigningKey = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Gh {
    & gh @args
    if ($LASTEXITCODE -ne 0) {
        throw "gh $($args -join ' ') scheiterte (Exit-Code $LASTEXITCODE)"
    }
}

if (-not $SigningKey -and -not $env:ATLAS_UPDATE_SIGNING_KEY) {
    throw 'Kein Schlüssel für die Versionsdatei: -SigningKey <PEM-Datei> angeben oder ATLAS_UPDATE_SIGNING_KEY setzen (docs/Release.md)'
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'GitHub-CLI gh nicht gefunden (https://cli.github.com, danach gh auth login)'
}
$Tag = "v$Version"
$Assets = (Invoke-Gh release view $Tag -R $Repository --json assets | ConvertFrom-Json).assets | ForEach-Object { $_.name }
$SourceName = "atlas-ide-expert-source-$Version.zip"
if ($SourceName -notin $Assets) {
    throw "Release $Tag hat keinen $SourceName; erst den Tag pushen und den Release-Workflow abwarten"
}

if (-not $Package) {
    $Package = Join-Path $Root "Output/Win64/Release/Bin/atlas-ide-expert-$Version.zip"
    & (Join-Path $PSScriptRoot 'New-ReleasePackage.ps1') -Version $Version -Root $Root -OutFile $Package
}
if (-not (Test-Path -LiteralPath $Package -PathType Leaf)) {
    throw "Paket fehlt: $Package"
}
$PackageName = "atlas-ide-expert-$Version.zip"
if ((Split-Path -Leaf $Package) -ne $PackageName) {
    throw "Das Paket muss $PackageName heißen (so steht es in der Versionsdatei)"
}
$Bin = Split-Path -Parent ([IO.Path]::GetFullPath($Package))

$Work = Join-Path ([IO.Path]::GetTempPath()) ('atlas-publish-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $Work | Out-Null
try {
    Invoke-Gh release download $Tag -R $Repository -p $SourceName -D $Work
    $VersionFile = Join-Path $Work 'atlas-version.json'
    & (Join-Path $PSScriptRoot 'New-VersionFile.ps1') -Version $Version -Repository $Repository -Ide $Ide `
        -SourceZip (Join-Path $Work $SourceName) -PackageZip $Package -OutFile $VersionFile | Write-Host
    & (Join-Path $PSScriptRoot 'Sign-VersionFile.ps1') -VersionFile $VersionFile -KeyFile $SigningKey -Root $Root

    $Upload = @($Package, $VersionFile, "$VersionFile.sig")
    foreach ($Name in 'AtlasServer.exe', 'AtlasServer.map') {
        $Path = Join-Path $Bin $Name
        if (Test-Path -LiteralPath $Path) {
            $Upload += $Path
        }
    }
    if ($PSCmdlet.ShouldProcess("Release $Tag", "Hochladen: $(($Upload | ForEach-Object { Split-Path -Leaf $_ }) -join ', ')")) {
        Invoke-Gh release upload $Tag -R $Repository --clobber @Upload
    }

    # Vorab-Kanal: nur ersetzen, wenn er auf diese Version zeigt; sonst ist dort schon eine neuere.
    $Channel = Join-Path $Work 'channel'
    New-Item -ItemType Directory -Force $Channel | Out-Null
    & gh release download update-channel -R $Repository -p 'atlas-version-beta.json' -D $Channel 2>$null
    $Current = Join-Path $Channel 'atlas-version-beta.json'
    $ChannelVersion = ''
    if (Test-Path -LiteralPath $Current) {
        $ChannelVersion = (Get-Content -Raw -LiteralPath $Current | ConvertFrom-Json).version
    }
    if ($ChannelVersion -and $ChannelVersion -ne $Version) {
        Write-Warning "Vorab-Kanal zeigt auf $ChannelVersion, nicht auf $Version; atlas-version-beta.json bleibt"
    } else {
        $Beta = Join-Path $Work 'atlas-version-beta.json'
        Copy-Item -LiteralPath $VersionFile $Beta
        Copy-Item -LiteralPath "$VersionFile.sig" "$Beta.sig"
        if ($PSCmdlet.ShouldProcess('Release update-channel', 'atlas-version-beta.json samt Signatur ersetzen')) {
            Invoke-Gh release upload update-channel -R $Repository --clobber $Beta "$Beta.sig"
        }
    }

    # Ohne Code-Signing-Zertifikat: sichtbarer Hinweis in den Release-Notizen (Zertifikat bleibt freiwillig).
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Updater = Join-Path $Work 'AtlasUpdate.exe'
    $Archive = [IO.Compression.ZipFile]::OpenRead($Package)
    try {
        $Entry = $Archive.GetEntry('AtlasUpdate.exe')
        if ($Entry) {
            [IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $Updater)
        }
    } finally {
        $Archive.Dispose()
    }
    $Signed = (Test-Path -LiteralPath $Updater) -and (Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue) -and
        ((Get-AuthenticodeSignature -LiteralPath $Updater).Status -eq 'Valid')
    if (-not $Signed) {
        $Notes = Join-Path $Work 'release-notes.md'
        & (Join-Path $PSScriptRoot 'Get-ReleaseNotes.ps1') -Version $Version -Root $Root -UnsignedBinaries |
            Set-Content -Encoding utf8 -LiteralPath $Notes
        if ($PSCmdlet.ShouldProcess("Release $Tag", 'Release-Notizen mit Hinweis auf unsignierte Binärdateien')) {
            Invoke-Gh release edit $Tag -R $Repository --notes-file $Notes
        }
    }
} finally {
    Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "Fertig: $Tag hat jetzt ein Paket für CompilerVersion $Ide; der Update-Installer kann es einspielen."
