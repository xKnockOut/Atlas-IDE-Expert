<#
.SYNOPSIS
    Legt einen Schlüssel für die Signatur der Versionsdatei an (#1519).

.DESCRIPTION
    Erzeugt einen ECDSA-P-256-Schlüssel, schreibt den privaten Teil als
    PKCS#8-PEM nach -OutFile und gibt den öffentlichen Teil als 128
    Hexziffern (X und Y) aus. Den öffentlichen Teil trägt man in
    Packages/Atlas.Common/Source/Updates/Atlas.Common.Updates.ManifestSignature.pas
    ein (cPrimaryKey bzw. cReserveKey), den privaten Teil als Geheimnis
    ATLAS_UPDATE_SIGNING_KEY im Repository und sicher verwahrt für das
    lokale Release. Ablauf und Wechsel in docs/Release.md.

    Die Datei darf nicht im Repository liegen; das Skript lehnt Ziele darin ab
    und überschreibt keine vorhandene Datei.

.EXAMPLE
    pwsh Tools/New-UpdateSigningKey.ps1 -OutFile $HOME\Atlas-Schluessel\update-haupt.pem
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $OutFile,
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Target = [IO.Path]::GetFullPath($OutFile)
$Repository = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($Target.StartsWith($Repository, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Der private Schlüssel gehört nicht ins Repository: $Target"
}
if (Test-Path -LiteralPath $Target) {
    throw "Datei gibt es schon: $Target"
}
$Folder = Split-Path -Parent $Target
if ($Folder) {
    New-Item -ItemType Directory -Force $Folder | Out-Null
}
$Ecdsa = [Security.Cryptography.ECDsa]::Create([Security.Cryptography.ECCurve+NamedCurves]::nistP256)
try {
    [IO.File]::WriteAllText($Target, $Ecdsa.ExportPkcs8PrivateKeyPem() + "`n", [Text.UTF8Encoding]::new($false))
    $Point = $Ecdsa.ExportParameters($false).Q
    $Public = ([Convert]::ToHexString($Point.X) + [Convert]::ToHexString($Point.Y)).ToLowerInvariant()
} finally {
    $Ecdsa.Dispose()
}
Write-Host "Privater Schlüssel: $Target"
Write-Host 'Öffentlicher Schlüssel (in Atlas.Common.Updates.ManifestSignature.pas eintragen):'
$Public
