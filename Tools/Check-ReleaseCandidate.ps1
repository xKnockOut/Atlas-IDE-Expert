<#
.SYNOPSIS
    Prüft vor einer stabilen Version, dass seit dem letzten Kandidaten nur Korrekturen kamen.

.DESCRIPTION
    Regel aus docs/Release.md, Abschnitt „Kandidaten“: Nach dem letzten Kandidaten kommen nur noch
    Korrekturen; ein Umbau bedeutet einen neuen Kandidaten; ein Kandidat liegt mindestens einen
    Arbeitstag, bevor die stabile Version daraus wird.

    Vergleichsstand ist der jüngste Vorab-Tag derselben Version (v<Version>-rc.N, v<Version>-beta.N),
    der in HEAD enthalten ist. Eine Patch-Version (x.y.z mit z > 0) ohne eigenen Kandidaten vergleicht
    gegen die vorige stabile Version derselben Reihe (v2.2.1 gegen v2.2.0), denn Patch-Versionen
    enthalten nur Korrekturen. Gezählt werden Units (*.pas) unter Packages/ und Application/:
    - jede neue Unit seit dem Vergleichsstand (Umbenennen zählt als neu);
    - mehr geänderte Units als -MaxChangedUnits;
    - ein Kandidat, der jünger ist als -MinCandidateHours;
    - kein Vergleichsstand (x.y.0 ohne Kandidat).

    Jeder dieser Punkte bricht ab, außer die Abweichung ist begründet: mit -Reason (Set-Version.ps1
    reicht den Wert durch und nennt die Zeile für den Commit-Text) oder mit -ReasonFromHistory über
    eine Zeile „Ohne neuen Kandidaten: <Grund>“ in einem Commit seit dem Vergleichsstand. So prüft
    der Release-Workflow das Tag. Mit Begründung werden die Befunde zu Warnungen.

    Versionen mit Suffix (Kandidaten selbst) prüft das Skript nicht. Ohne -Version gilt die Version im
    Quelltext (TAtlasVersion.cVersion); ist sie schon als Tag veröffentlicht, gibt es nichts zu prüfen.

    Exit-Code 0: in Ordnung oder begründet, 1: Verstoß.

.PARAMETER Reason
    Begründung, warum die stabile Version ohne neuen Kandidaten kommt.

.PARAMETER ReasonFromHistory
    Begründung aus den Commit-Texten seit dem Vergleichsstand lesen (Zeile „Ohne neuen Kandidaten: …“).

.PARAMETER SelfTest
    Prüft die Regel an einem Wegwerf-Repository mit Tags und Commits.

.EXAMPLE
    pwsh Tools/Check-ReleaseCandidate.ps1 -Version 2.3.0
    pwsh Tools/Check-ReleaseCandidate.ps1 -Version 2.3.0 -Reason 'Umbenennen eines Bezeichners in 40 Units'
#>
[CmdletBinding()]
param(
    [string] $Version = '',
    [string] $Reason = '',
    [switch] $ReasonFromHistory,
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [int] $MaxChangedUnits = 25,
    [double] $MinCandidateHours = 20,
    [switch] $SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cReasonPrefix = 'Ohne neuen Kandidaten:'
$cUnitPaths = @(':(glob)Packages/**/*.pas', ':(glob)Application/**/*.pas')

function Invoke-Git([string] $Repo, [string[]] $Arguments) {
    $mOutput = @(& git -C $Repo @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') ist gescheitert" }
    return , $mOutput
}

# Jüngster Vorab-Tag der Version in HEAD, sonst bei einer Patch-Version die vorige stabile Version der Reihe.
function Get-ComparisonTag([string] $Repo, [string] $Version) {
    $mCandidates = Invoke-Git $Repo @('tag', '--list', "v$Version-*", '--merged', 'HEAD', '--sort=-v:refname')
    if ($mCandidates.Count -gt 0) { return [pscustomobject]@{ Tag = $mCandidates[0]; IsCandidate = $true } }
    $mParts = $Version.Split('.')
    if ([int]$mParts[2] -eq 0) { return $null }
    $mSeries = "v$($mParts[0]).$($mParts[1])."
    $mSeriesTags = Invoke-Git $Repo @('tag', '--list', "$mSeries*", '--merged', 'HEAD', '--sort=-v:refname')
    $mStable = @($mSeriesTags | Where-Object { $_ -match '^v\d+\.\d+\.\d+$' -and $_ -ne "v$Version" })
    if ($mStable.Count -eq 0) { return $null }
    return [pscustomobject]@{ Tag = $mStable[0]; IsCandidate = $false }
}

function Get-HistoryReason([string] $Repo, [string] $Range) {
    $mText = Invoke-Git $Repo @('log', '--format=%B', $Range)
    foreach ($mLine in $mText) {
        if ($mLine -match ('^\s*' + [regex]::Escape($cReasonPrefix) + '\s*(\S.*?)\s*$')) { return $Matches[1] }
    }
    return ''
}

# Liefert die Befunde und den Vergleichsstand; wirft nichts bei Verstößen.
function Test-ReleaseCandidate([string] $Repo, [string] $Version, [int] $MaxChanged, [double] $MinHours, [datetime] $Now) {
    $mResult = [pscustomobject]@{ Base = ''; Problems = [System.Collections.Generic.List[string]]::new(); HistoryReason = '' }
    $mBase = Get-ComparisonTag $Repo $Version
    if ($null -eq $mBase) {
        $mResult.Problems.Add("Für $Version gibt es keinen Kandidaten; erst v$Version-rc.1 veröffentlichen")
        return $mResult
    }
    $mResult.Base = $mBase.Tag
    $mRange = "$($mBase.Tag)..HEAD"
    $mNew = Invoke-Git $Repo (@('diff', '--no-renames', '--diff-filter=A', '--name-only', $mRange, '--') + $cUnitPaths)
    $mChanged = Invoke-Git $Repo (@('diff', '--no-renames', '--name-only', $mRange, '--') + $cUnitPaths)
    if ($mNew.Count -gt 0) {
        $mList = @($mNew | Select-Object -First 5) -join ', '
        if ($mNew.Count -gt 5) { $mList += ', …' }
        $mResult.Problems.Add("$($mNew.Count) neue Units seit $($mBase.Tag) ($mList)")
    }
    if ($mChanged.Count -gt $MaxChanged) {
        $mResult.Problems.Add("$($mChanged.Count) geänderte Units seit $($mBase.Tag) (Grenze $MaxChanged)")
    }
    if ($mBase.IsCandidate) {
        $mCreated = [int64](Invoke-Git $Repo @('for-each-ref', '--format=%(creatordate:unix)', "refs/tags/$($mBase.Tag)"))[0]
        $mHours = ($Now.ToUniversalTime() - [DateTimeOffset]::FromUnixTimeSeconds($mCreated).UtcDateTime).TotalHours
        if ($mHours -lt $MinHours) {
            $mResult.Problems.Add(("Kandidat $($mBase.Tag) liegt erst {0:0.0} Stunden (mindestens $MinHours)" -f $mHours))
        }
    }
    $mResult.HistoryReason = Get-HistoryReason $Repo $mRange
    return $mResult
}

function New-SelfTestRepo([string] $Path) {
    New-Item -ItemType Directory -Force (Join-Path $Path 'Packages/A/Source') | Out-Null
    Invoke-Git $Path @('init', '-q', '-b', 'main') | Out-Null
    Invoke-Git $Path @('config', 'user.email', 'selbsttest@example.invalid') | Out-Null
    Invoke-Git $Path @('config', 'user.name', 'Selbsttest') | Out-Null
    Invoke-Git $Path @('config', 'commit.gpgsign', 'false') | Out-Null
    Invoke-Git $Path @('config', 'tag.gpgsign', 'false') | Out-Null
    foreach ($mIndex in 1..30) { Set-Content -LiteralPath (Join-Path $Path "Packages/A/Source/U$mIndex.pas") -Value "unit U$mIndex;" }
    Invoke-Git $Path @('add', '-A') | Out-Null
    Invoke-Git $Path @('commit', '-q', '-m', 'Anfang') | Out-Null
}

function Add-SelfTestCommit([string] $Path, [string[]] $Files, [string] $Message) {
    foreach ($mFile in $Files) { Add-Content -LiteralPath (Join-Path $Path $mFile) -Value '// geändert' }
    Invoke-Git $Path @('add', '-A') | Out-Null
    Invoke-Git $Path @('commit', '-q', '-m', $Message) | Out-Null
}

$script:SelfTestRoot = ''
$script:SelfTestCases = 0
$script:SelfTestFailed = 0

function Assert-SelfTestCase([string] $Name, [string] $Version, [int] $Expected, [datetime] $Now, [string] $ExpectedReason = '') {
    $script:SelfTestCases++
    $mFound = Test-ReleaseCandidate $script:SelfTestRoot $Version 25 20 $Now
    if ($mFound.Problems.Count -ne $Expected -or $mFound.HistoryReason -ne $ExpectedReason) {
        Write-Host ("::error::Selbsttest '$Name': $($mFound.Problems.Count) Befunde statt $Expected, " +
            "Begründung '$($mFound.HistoryReason)' ($($mFound.Problems -join '; '))")
        $script:SelfTestFailed++
    }
}

function Invoke-SelfTest {
    $mRoot = Join-Path ([IO.Path]::GetTempPath()) ('atlas-kandidat-' + [guid]::NewGuid().ToString('N'))
    $script:SelfTestRoot = $mRoot
    $mLater = (Get-Date).AddDays(2)
    try {
        New-SelfTestRepo $mRoot
        Assert-SelfTestCase 'kein Kandidat' '1.0.0' 1 $mLater
        Invoke-Git $mRoot @('tag', 'v1.0.0-rc.1') | Out-Null
        Assert-SelfTestCase 'Kandidat ohne Änderung' '1.0.0' 0 $mLater
        Assert-SelfTestCase 'Kandidat jünger als ein Arbeitstag' '1.0.0' 1 (Get-Date)
        Add-SelfTestCommit $mRoot @('Packages/A/Source/U1.pas') 'Korrektur'
        Assert-SelfTestCase 'eine Korrektur' '1.0.0' 0 $mLater
        Set-Content -LiteralPath (Join-Path $mRoot 'Packages/A/Source/Neu.pas') -Value 'unit Neu;'
        Add-SelfTestCommit $mRoot @() "Umbau`n`n$cReasonPrefix Neue Unit für den Fehler im Start"
        Assert-SelfTestCase 'neue Unit, begründet im Commit' '1.0.0' 1 $mLater 'Neue Unit für den Fehler im Start'
        Invoke-Git $mRoot @('tag', 'v1.0.0-rc.2') | Out-Null
        Add-SelfTestCommit $mRoot @(1..26 | ForEach-Object { "Packages/A/Source/U$_.pas" }) 'Großer Umbau'
        Assert-SelfTestCase 'zu viele geänderte Units nach rc.2' '1.0.0' 1 $mLater
        Assert-SelfTestCase 'Kandidat einer anderen Version zählt nicht' '1.1.0' 1 $mLater
        Invoke-Git $mRoot @('tag', 'v1.0.0') | Out-Null
        Add-SelfTestCommit $mRoot @('Packages/A/Source/U2.pas') 'Korrektur nach 1.0.0'
        Assert-SelfTestCase 'Patch-Version gegen die vorige stabile Version' '1.0.1' 0 $mLater
        Invoke-Git $mRoot @('mv', 'Packages/A/Source/U3.pas', 'Packages/A/Source/U3Neu.pas') | Out-Null
        Add-SelfTestCommit $mRoot @() 'Umbenannt'
        Assert-SelfTestCase 'Umbenennen zählt als neue Unit' '1.0.1' 1 $mLater
    }
    finally {
        Remove-Item -LiteralPath $mRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($script:SelfTestFailed -gt 0) { exit 1 }
    Write-Host "Selbsttest: $($script:SelfTestCases) Fälle zur Regel der Kandidaten bestanden."
    exit 0
}

if ($SelfTest) { Invoke-SelfTest }

if (-not $Version) {
    $mUnit = Join-Path $Root 'Packages/Atlas.Text/Source/Product/Atlas.Text.Product.Version.pas'
    $mMatch = [regex]::Match([IO.File]::ReadAllText($mUnit), "cVersion\s*=\s*'([^']+)'")
    if ($mMatch.Success) { $Version = $mMatch.Groups[1].Value }
    $mTags = Invoke-Git $Root @('tag', '--list', "v$Version")
    if ($mTags.Count -gt 0) {
        Write-Host "Version $Version ist schon veröffentlicht (Tag v$Version); nichts zu prüfen."
        exit 0
    }
}
if ($Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') {
    Write-Host "::error::'$Version' ist keine SemVer-Version"
    exit 1
}
if ($Version.Contains('-')) {
    Write-Host "Kandidat ${Version}: keine Prüfung gegen einen Vorgänger."
    exit 0
}

$Found = Test-ReleaseCandidate $Root $Version $MaxChangedUnits $MinCandidateHours (Get-Date)
$Why = $Reason.Trim()
if (-not $Why -and $ReasonFromHistory) { $Why = $Found.HistoryReason }
if ($Found.Problems.Count -eq 0) {
    Write-Host "Seit $($Found.Base) nur Korrekturen: $Version darf ohne neuen Kandidaten erscheinen."
    exit 0
}
if ($Why) {
    $Found.Problems | ForEach-Object { Write-Host "::warning::$_ (begründet: $Why)" }
    exit 0
}
$Found.Problems | ForEach-Object { Write-Host "::error::$_" }
Write-Host ("::error::Seit dem letzten Kandidaten ist mehr geschehen als Korrekturen. Neuen Kandidaten " +
    "veröffentlichen oder begründen: -Reason bzw. eine Zeile '$cReasonPrefix <Grund>' im Commit-Text.")
exit 1
