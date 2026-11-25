<#
.SYNOPSIS
    Prüft New-UpdateSigningKey.ps1 und Sign-VersionFile.ps1 (#1519):
    Signieren, Prüfen, Abbruch bei fremdem Schlüssel, veränderter Datei und
    BOM, und dass die eingebetteten öffentlichen Schlüssel gültig sind.

.DESCRIPTION
    Legt in einem temporären Ordner außerhalb des Repositorys zwei
    Testschlüssel an und signiert eine Versionsdatei damit. Zusätzlich prüft
    es die Signatur aus Atlas.Windows.Updates.Adapters.Trust.Tests (erzeugt mit
    OpenSSL): Sie muss auch hier gelten, sonst passen das Format des Skripts
    und das von BCryptVerifySignature nicht zusammen.

.EXAMPLE
    pwsh Tools/Test-VersionFileSignature.ps1
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$NewKey = Join-Path $PSScriptRoot 'New-UpdateSigningKey.ps1'
$Sign = Join-Path $PSScriptRoot 'Sign-VersionFile.ps1'
$Failures = [System.Collections.Generic.List[string]]::new()

function Expect-Failure([string] $Case, [string] $Pattern, [scriptblock] $Action) {
    try {
        & $Action 6>$null | Out-Null
        $Failures.Add("${Case}: kein Abbruch")
    } catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            $Failures.Add("${Case}: falsche Meldung: $($_.Exception.Message)")
        }
    }
}

$Work = Join-Path ([IO.Path]::GetTempPath()) ('atlas-sign-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $Work | Out-Null
try {
    $KeyA = Join-Path $Work 'a.pem'
    $KeyB = Join-Path $Work 'b.pem'
    $PublicA = (& $NewKey -OutFile $KeyA -Root $Root 6>$null)
    $PublicB = (& $NewKey -OutFile $KeyB -Root $Root 6>$null)
    if ($PublicA -notmatch '^[0-9a-f]{128}$' -or $PublicA -eq $PublicB) {
        $Failures.Add("Schlüssel: öffentlicher Teil unbrauchbar: $PublicA")
    }
    Expect-Failure 'Schlüssel überschreiben' 'gibt es schon' { & $NewKey -OutFile $KeyA -Root $Root }
    Expect-Failure 'Schlüssel im Repository' 'nicht ins Repository' {
        & $NewKey -OutFile (Join-Path $Root 'Output/schluessel.pem') -Root $Root
    }

    $Json = Join-Path $Work 'atlas-version.json'
    [IO.File]::WriteAllText($Json, '{"version":"2.3.0"}' + "`n", [Text.UTF8Encoding]::new($false))
    & $Sign -VersionFile $Json -KeyFile $KeyB -PublicKeys $PublicA, $PublicB 6>$null
    $Hex = [IO.File]::ReadAllText("$Json.sig")
    if ($Hex -notmatch '^[0-9a-f]{128}\n$') {
        $Failures.Add("Signatur: Format falsch: $Hex")
    }
    & $Sign -VersionFile $Json -Verify -PublicKeys $PublicA, $PublicB 6>$null
    Expect-Failure 'Fremder Schlüssel' 'keinem eingebetteten' { & $Sign -VersionFile $Json -KeyFile $KeyB -PublicKeys $PublicA }
    Expect-Failure 'Ohne Schlüssel' 'Kein privater Schlüssel' {
        $Saved = $env:ATLAS_UPDATE_SIGNING_KEY
        $env:ATLAS_UPDATE_SIGNING_KEY = ''
        try { & $Sign -VersionFile $Json -PublicKeys $PublicA } finally { $env:ATLAS_UPDATE_SIGNING_KEY = $Saved }
    }
    # Schlüssel aus der Umgebung wie im Release-Workflow.
    $Saved = $env:ATLAS_UPDATE_SIGNING_KEY
    $env:ATLAS_UPDATE_SIGNING_KEY = [IO.File]::ReadAllText($KeyA)
    try {
        & $Sign -VersionFile $Json -PublicKeys $PublicA 6>$null
    } finally {
        $env:ATLAS_UPDATE_SIGNING_KEY = $Saved
    }
    [IO.File]::WriteAllText($Json, '{"version":"2.3.1"}' + "`n", [Text.UTF8Encoding]::new($false))
    Expect-Failure 'Veränderte Datei' 'passt zu keinem' { & $Sign -VersionFile $Json -Verify -PublicKeys $PublicA }
    [IO.File]::WriteAllText($Json, '{"version":"2.3.0"}', [Text.UTF8Encoding]::new($true))
    Expect-Failure 'BOM' 'mit BOM' { & $Sign -VersionFile $Json -KeyFile $KeyA -PublicKeys $PublicA }

    # Gegenprobe mit der OpenSSL-Signatur aus den Delphi-Tests (dieselbe Datei, Schlüssel A der Tests).
    $Tests = [IO.File]::ReadAllText((Join-Path $Root 'Tests/Windows/Updates/Atlas.Windows.Updates.Adapters.Trust.Tests.pas'))
    $Constant = {
        param([string] $Name)
        if ($Tests -notmatch "(?s)\b$Name\s*=\s*((?:'[0-9a-f]*'\s*\+?\s*)+);") {
            throw "$Name fehlt in den Trust-Tests"
        }
        (([regex]::Matches($Matches[1], "'([0-9a-f]*)'") | ForEach-Object { $_.Groups[1].Value }) -join '')
    }
    [IO.File]::WriteAllText($Json, '{"version":"2.3.0"}' + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText("$Json.sig", (& $Constant 'cSignatureA') + "`n")
    try {
        & $Sign -VersionFile $Json -Verify -PublicKeys (& $Constant 'cKeyA') 6>$null
    } catch {
        $Failures.Add("Gegenprobe OpenSSL: $($_.Exception.Message)")
    }

    # Eingebettete Schlüssel: zwei verschiedene Punkte auf P-256.
    $Unit = [IO.File]::ReadAllText((Join-Path $Root 'Packages/Atlas.Common/Source/Updates/Atlas.Common.Updates.ManifestSignature.pas'))
    $Embedded = foreach ($Name in 'cPrimaryKey', 'cReserveKey') {
        if ($Unit -match "(?s)\b$Name\s*=\s*((?:'[0-9a-fA-F]*'\s*\+?\s*)+);") {
            (([regex]::Matches($Matches[1], "'([0-9a-fA-F]*)'") | ForEach-Object { $_.Groups[1].Value }) -join '')
        }
    }
    $Embedded = @($Embedded | Where-Object { $_ })
    if ($Embedded.Count -ne 2 -or $Embedded[0] -eq $Embedded[1]) {
        $Failures.Add("Eingebettete Schlüssel: zwei verschiedene erwartet, gefunden $($Embedded.Count)")
    }
    foreach ($Key in $Embedded) {
        try {
            $Point = [Convert]::FromHexString($Key)
            $Parameters = [Security.Cryptography.ECParameters]::new()
            $Parameters.Curve = [Security.Cryptography.ECCurve+NamedCurves]::nistP256
            $Q = [Security.Cryptography.ECPoint]::new()
            $Q.X = $Point[0..31]
            $Q.Y = $Point[32..63]
            $Parameters.Q = $Q
            $Parameters.Validate()
            [Security.Cryptography.ECDsa]::Create($Parameters).Dispose()
        } catch {
            $Failures.Add("Eingebetteter Schlüssel ungültig: $Key ($($_.Exception.Message))")
        }
    }
} finally {
    Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($Failures.Count -gt 0) {
    $Failures | ForEach-Object { Write-Host "FEHLER: $_" }
    exit 1
}
Write-Host 'Signatur der Versionsdatei: alle Fälle in Ordnung'
