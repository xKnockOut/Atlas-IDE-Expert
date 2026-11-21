<#
.SYNOPSIS
    Signiert die Versionsdatei atlas-version.json mit dem eigenen Schlüssel
    für Updates (#1519) und schreibt <Versionsdatei>.sig daneben.

.DESCRIPTION
    ECDSA P-256 über SHA-256 der Bytes der Datei, unabhängig von einem
    Code-Signing-Zertifikat. Die Signaturdatei enthält r und s (je 32 Byte) als
    128 kleine Hexziffern und ein Zeilenende. AtlasUpdate.exe prüft sie gegen
    die öffentlichen Schlüssel in
    Packages/Atlas.Common/Source/Updates/Atlas.Common.Updates.ManifestSignature.pas,
    bevor es die Versionsdatei auswertet.

    Der private Schlüssel (PKCS#8, PEM) kommt aus -KeyFile oder aus der
    Umgebungsvariablen ATLAS_UPDATE_SIGNING_KEY (Inhalt der PEM-Datei; im
    Release-Workflow das gleichnamige Geheimnis). Er liegt nie im Repository.

    Nach dem Signieren prüft das Skript die Signatur gegen die eingebetteten
    öffentlichen Schlüssel und bricht ab, wenn keiner passt: Eine Signatur, die
    kein Updater annimmt, ließe jedes Update scheitern.

    Mit -Verify signiert es nicht, sondern prüft eine vorhandene Signaturdatei.

.EXAMPLE
    pwsh Tools/Sign-VersionFile.ps1 -VersionFile atlas-version.json -KeyFile $HOME\Atlas-Schluessel\update-haupt.pem

.EXAMPLE
    pwsh Tools/Sign-VersionFile.ps1 -VersionFile atlas-version.json -Verify
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $VersionFile,
    [string] $KeyFile = '',
    [switch] $Verify,
    # Nur für Tests: öffentliche Schlüssel statt der eingebetteten.
    [string[]] $PublicKeys = @(),
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-Hex([string] $Text) {
    $Text = $Text.Trim()
    if ($Text.Length % 2 -ne 0 -or $Text -notmatch '^[0-9a-fA-F]*$') {
        throw "Keine Hexziffern: $Text"
    }
    [Convert]::FromHexString($Text)
}

function Get-EmbeddedKeys([string] $Root) {
    $Unit = Join-Path $Root 'Packages/Atlas.Common/Source/Updates/Atlas.Common.Updates.ManifestSignature.pas'
    $Text = [IO.File]::ReadAllText($Unit)
    $Keys = foreach ($Name in 'cPrimaryKey', 'cReserveKey') {
        # Konstante über eine oder mehrere Zeilen: '…' + '…';
        if ($Text -notmatch "(?s)\b$Name\s*=\s*((?:'[0-9a-fA-F]*'\s*\+?\s*)+);") {
            throw "$Name nicht gefunden in $Unit"
        }
        (([regex]::Matches($Matches[1], "'([0-9a-fA-F]*)'") | ForEach-Object { $_.Groups[1].Value }) -join '')
    }
    @($Keys | Where-Object { $_ })
}

function Test-Signature([byte[]] $Data, [byte[]] $Signature, [string[]] $Keys) {
    foreach ($Key in $Keys) {
        $Point = ConvertFrom-Hex $Key
        if ($Point.Length -ne 64) {
            continue
        }
        $Parameters = [Security.Cryptography.ECParameters]::new()
        $Parameters.Curve = [Security.Cryptography.ECCurve+NamedCurves]::nistP256
        $Q = [Security.Cryptography.ECPoint]::new()
        $Q.X = $Point[0..31]
        $Q.Y = $Point[32..63]
        $Parameters.Q = $Q
        $Ecdsa = [Security.Cryptography.ECDsa]::Create($Parameters)
        try {
            if ($Ecdsa.VerifyData($Data, $Signature, [Security.Cryptography.HashAlgorithmName]::SHA256)) {
                return $true
            }
        } finally {
            $Ecdsa.Dispose()
        }
    }
    $false
}

if (-not (Test-Path -LiteralPath $VersionFile -PathType Leaf)) {
    throw "Versionsdatei fehlt: $VersionFile"
}
$Data = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $VersionFile))
if ($Data.Length -ge 3 -and $Data[0] -eq 0xEF -and $Data[1] -eq 0xBB -and $Data[2] -eq 0xBF) {
    # Das Plugin liest die Datei als UTF-8-Text; ein BOM fiele dabei weg, die Signatur passte nicht mehr.
    throw "Versionsdatei mit BOM: $VersionFile (New-VersionFile.ps1 schreibt UTF-8 ohne BOM)"
}
$Keys = @(if ($PublicKeys.Count -gt 0) { $PublicKeys } else { Get-EmbeddedKeys $Root })
if ($Keys.Count -eq 0) {
    throw 'Keine öffentlichen Schlüssel in Atlas.Common.Updates.ManifestSignature.pas eingetragen (docs/Release.md)'
}
$SignatureFile = "$VersionFile.sig"

if ($Verify) {
    if (-not (Test-Path -LiteralPath $SignatureFile -PathType Leaf)) {
        throw "Signaturdatei fehlt: $SignatureFile"
    }
    $Signature = ConvertFrom-Hex ([IO.File]::ReadAllText((Resolve-Path -LiteralPath $SignatureFile)))
    if (-not (Test-Signature $Data $Signature $Keys)) {
        throw "Signatur passt zu keinem eingebetteten Schlüssel: $SignatureFile"
    }
    Write-Host "Signatur in Ordnung: $SignatureFile"
    return
}

$Pem = if ($KeyFile) { [IO.File]::ReadAllText((Resolve-Path -LiteralPath $KeyFile)) } else { $env:ATLAS_UPDATE_SIGNING_KEY }
if ([string]::IsNullOrWhiteSpace($Pem)) {
    throw 'Kein privater Schlüssel: -KeyFile angeben oder ATLAS_UPDATE_SIGNING_KEY setzen (docs/Release.md)'
}
$Ecdsa = [Security.Cryptography.ECDsa]::Create()
try {
    $Ecdsa.ImportFromPem($Pem)
    if ($Ecdsa.KeySize -ne 256) {
        throw "Schlüssel hat $($Ecdsa.KeySize) Bit, erwartet ist P-256"
    }
    # IEEE P1363: r und s je 32 Byte, wie BCryptVerifySignature sie erwartet.
    $Signature = $Ecdsa.SignData($Data, [Security.Cryptography.HashAlgorithmName]::SHA256)
} finally {
    $Ecdsa.Dispose()
}
if (-not (Test-Signature $Data $Signature $Keys)) {
    throw ('Der private Schlüssel gehört zu keinem eingebetteten öffentlichen Schlüssel; die Signatur würde jedes ' +
        'Update scheitern lassen (docs/Release.md, Schlüssel wechseln)')
}
$Hex = [Convert]::ToHexString($Signature).ToLowerInvariant()
[IO.File]::WriteAllText([IO.Path]::GetFullPath($SignatureFile), $Hex + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "Signiert: $SignatureFile"
