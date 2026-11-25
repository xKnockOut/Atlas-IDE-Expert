<#
.SYNOPSIS
    Prüft, dass die Zahl der Aufwärm-Routinen ([SetupFixture]) in den Tests nur sinkt und gemeinsame Sperren nicht
    von Hand vorgewärmt werden.

.DESCRIPTION
    Ein [SetupFixture], das den eigenen Test einmal ungemessen vorweg laufen lässt, nimmt jede Belegung des
    ersten Durchlaufs aus der Messung des Leckmonitors, ohne zu nennen, was belegt bleibt. Bekannte
    Einmal-Belegungen gehören stattdessen mit ihrem Besitzer nach Tests/Support/Atlas.Tests.FirstUse.pas;
    ob sie bis zum Programmende leben und dort freigegeben werden, prüft der Speicherrest beim Beenden
    (TShutdownLeaks.Expect in Tests/Atlas.Tests.dpr, ausgewertet von Tools/Build-Test.ps1).

    Die Prüfung führt jede Routine mit [SetupFixture] unter Tests/ als "Datei: Klasse.Methode" und vergleicht
    mit Tools/TestWarmUps.baseline.json:
    - Eine Routine, die nicht in der Baseline steht, ist ein Verstoß (neues Aufwärmen).
    - Eine Routine der Baseline, die es nicht mehr gibt, ist ebenfalls ein Verstoß: Mit -Update die Baseline im
      selben Pull Request senken, damit sie nicht wieder wachsen kann.
    Ausgenommen sind Projekte, die Atlas als Prüfling dienen (Referenzprojekt, Fälle für dcc-Meldungen).

    Zweitens darf in Packages/, Application/ und Tests/ nirgends TMonitor.Enter(X) direkt von TMonitor.Exit(X)
    gefolgt sein: Gemeinsame Sperren mit schon angelegtem Monitor-Datensatz entstehen nur über
    TAtlasSharedLock.New (Atlas.Text.Locked), Einmal-Belegungen für die Messung stehen in TFirstUse.

    Exit-Code 0: keine Verstöße, 1: mindestens ein Verstoß.

.EXAMPLE
    pwsh Tools/Check-TestWarmUps.ps1

.EXAMPLE
    pwsh Tools/Check-TestWarmUps.ps1 -Update

.EXAMPLE
    pwsh Tools/Check-TestWarmUps.ps1 -SelfTest
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    # Schreibt die Baseline neu (nur zum Senken verwenden).
    [switch] $Update,
    [switch] $SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ordner (relativ zum Stamm, mit /) mit Quelltext, den Atlas als Prüfling liest.
$Exempt = @(
    'Tests/DccFaelle/',
    'Tests/Compilermeldungen/',
    'Tests/Referenzprojekt/'
)

# Units, in denen das Paar aus TMonitor.Enter und TMonitor.Exit stehen darf: die Routine selbst und ihr Test.
$LockOwners = @(
    'Packages/Atlas.Text/Source/Locked/Atlas.Text.Locked.pas',
    'Tests/Text/Atlas.Text.Locked.Tests.pas'
)

# Liefert die Zeilennummern, an denen TMonitor.Enter(X) direkt (nur Leerzeilen und Kommentare dazwischen) von
# TMonitor.Exit(X) mit demselben X gefolgt ist.
function Get-LockWarmUps([string] $Text) {
    $Found = [System.Collections.Generic.List[int]]::new()
    $Lines = $Text -split "`r?`n"
    $Pattern = '^\s*(?:System\.)?TMonitor\.{0}\(\s*([\w.]+)\s*\)\s*;\s*(?://.*)?$'
    for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
        if ($Lines[$Index] -notmatch ($Pattern -f 'Enter')) {
            continue
        }
        $Target = $Matches[1]
        $Next = $Index + 1
        while ($Next -lt $Lines.Count -and ($Lines[$Next].Trim() -eq '' -or $Lines[$Next].Trim().StartsWith('//'))) {
            $Next++
        }
        if ($Next -lt $Lines.Count -and $Lines[$Next] -match ($Pattern -f 'Exit') -and $Matches[1] -eq $Target) {
            $Found.Add($Index + 1)
        }
    }
    $Found
}

# Liefert "Klasse.Methode" je Routine mit [SetupFixture] im Text einer Unit.
function Get-WarmUps([string] $Text) {
    $Found = [System.Collections.Generic.List[string]]::new()
    $Class = ''
    $Pending = $false
    foreach ($Line in ($Text -split "`r?`n")) {
        $Trimmed = $Line.Trim()
        if ($Trimmed -match '^(T\w+)\s*=\s*class\b') {
            $Class = $Matches[1]
            $Pending = $false
            continue
        }
        if ($Trimmed -match '^\[[^\]]*\bSetupFixture\b[^\]]*\]') {
            $Pending = $true
        }
        if ($Pending -and $Trimmed -match '^(?:\[[^\]]*\]\s*)*procedure\s+(\w+)\s*;') {
            $Found.Add("$Class.$($Matches[1])")
            $Pending = $false
            continue
        }
        if ($Pending -and $Trimmed -ne '' -and -not $Trimmed.StartsWith('[') -and -not $Trimmed.StartsWith('//')) {
            $Pending = $false
        }
        if ($Trimmed -match '^implementation\b') {
            break
        }
    }
    $Found
}

if ($SelfTest) {
    $Cases = @(
        @{ Name = 'eine Routine'; Count = 1; Text = "type`n  [TestFixture]`n  TA = class`n  public`n    [SetupFixture]`n    procedure WarmUp;`n    [Test]`n    procedure Eins;`n  end;`nimplementation" },
        @{ Name = 'Attribut davor'; Count = 1; Text = "type`n  TA = class`n    [SetupFixture]`n    // Grund`n    [Category('X')]`n    procedure Vorher;`n  end;`nimplementation" },
        @{ Name = 'zwei Klassen'; Count = 2; Text = "type`n  TA = class`n    [SetupFixture] procedure A;`n  end;`n  TB = class`n    [SetupFixture]`n    procedure B;`n  end;`nimplementation" },
        @{ Name = 'nur TearDown'; Count = 0; Text = "type`n  TA = class`n    [TearDownFixture]`n    procedure Ende;`n    [TearDown]`n    procedure T;`n  end;`nimplementation" },
        @{ Name = 'Implementierung zählt nicht'; Count = 0; Text = "type`n  TA = class`n  end;`nimplementation`n// [SetupFixture]`n// procedure X;" }
    )
    $Failed = 0
    foreach ($Case in $Cases) {
        $Got = @(Get-WarmUps $Case.Text)
        if ($Got.Count -ne $Case.Count) {
            Write-Host "FEHLER: $($Case.Name): $($Got.Count) statt $($Case.Count) Routinen ($($Got -join '; '))"
            $Failed++
        }
    }
    if (@(Get-WarmUps $Cases[2].Text) -join ',' -ne 'TA.A,TB.B') {
        Write-Host 'FEHLER: zwei Klassen: falsche Namen'
        $Failed++
    }
    $LockCases = @(
        @{ Name = 'Paar'; Lines = '2'; Text = "  FLock := TObject.Create;`n  TMonitor.Enter(FLock);`n  TMonitor.Exit(FLock);" },
        @{ Name = 'mit System und Kommentar'; Lines = '1'; Text = "System.TMonitor.Enter(A.B);`n  // Grund`n`nSystem.TMonitor.Exit(A.B);" },
        @{ Name = 'Sperre mit Rumpf'; Lines = ''; Text = "  TMonitor.Enter(FLock);`n  try`n    X;`n  finally`n    TMonitor.Exit(FLock);`n  end;" },
        @{ Name = 'andere Sperre'; Lines = ''; Text = "  TMonitor.Enter(FA);`n  TMonitor.Exit(FB);" },
        @{ Name = 'Routine'; Lines = ''; Text = "  FLock := TAtlasSharedLock.New;" }
    )
    foreach ($Case in $LockCases) {
        $Got = @(Get-LockWarmUps $Case.Text) -join ','
        if ($Got -ne $Case.Lines) {
            Write-Host "FEHLER: Sperre $($Case.Name): Zeilen '$Got' statt '$($Case.Lines)'"
            $Failed++
        }
    }
    if ($Failed -gt 0) {
        exit 1
    }
    Write-Host 'Selbsttest der Prüfung auf Aufwärm-Routinen bestanden.' -ForegroundColor Green
    exit 0
}

$BaselineFile = Join-Path $Root 'Tools/TestWarmUps.baseline.json'
$Current = [System.Collections.Generic.List[string]]::new()
$Files = @(Get-ChildItem -Path (Join-Path $Root 'Tests') -Recurse -File -Filter '*.pas' |
    Where-Object { $_.FullName -notmatch '[\\/](Output|__history)[\\/]' })
foreach ($File in $Files) {
    $Relative = [IO.Path]::GetRelativePath($Root, $File.FullName).Replace('\', '/')
    if (@($Exempt | Where-Object { $Relative.StartsWith($_) }).Count -gt 0) {
        continue
    }
    $Text = [IO.File]::ReadAllText($File.FullName)
    if (-not $Text.Contains('SetupFixture')) {
        continue
    }
    foreach ($Name in @(Get-WarmUps $Text)) {
        $Current.Add("${Relative}: $Name")
    }
}
$Sorted = @($Current | Sort-Object -Unique -Culture 'en-US' -CaseSensitive)

$LockWarmUps = [System.Collections.Generic.List[string]]::new()
$Sources = @(foreach ($Folder in @('Packages', 'Application', 'Tests')) {
        Get-ChildItem -Path (Join-Path $Root $Folder) -Recurse -File -Include '*.pas', '*.dpr', '*.dpk' |
            Where-Object { $_.FullName -notmatch '[\\/](Output|__history)[\\/]' }
    })
foreach ($File in $Sources) {
    $Relative = [IO.Path]::GetRelativePath($Root, $File.FullName).Replace('\', '/')
    if ($LockOwners -contains $Relative -or @($Exempt | Where-Object { $Relative.StartsWith($_) }).Count -gt 0) {
        continue
    }
    $Text = [IO.File]::ReadAllText($File.FullName)
    if (-not $Text.Contains('TMonitor.Exit')) {
        continue
    }
    foreach ($Line in @(Get-LockWarmUps $Text)) {
        $LockWarmUps.Add("${Relative}:$Line")
    }
}

if ($Update) {
    $Json = [ordered]@{ count = $Sorted.Count; warmUps = $Sorted } | ConvertTo-Json -Depth 3
    [IO.File]::WriteAllText($BaselineFile, $Json.Replace("`r`n", "`n") + "`n", [Text.UTF8Encoding]::new($false))
    Write-Host "Baseline mit $($Sorted.Count) Aufwärm-Routinen geschrieben: $BaselineFile" -ForegroundColor Green
    exit 0
}

$Known = @()
if (Test-Path $BaselineFile) {
    $Known = @((Get-Content $BaselineFile -Raw -Encoding UTF8 | ConvertFrom-Json).warmUps)
}
$New = @($Sorted | Where-Object { $Known -notcontains $_ })
$Gone = @($Known | Where-Object { $Sorted -notcontains $_ })
if ($New.Count -gt 0) {
    Write-Host 'Neue Aufwärm-Routinen ([SetupFixture]) in den Tests:' -ForegroundColor Red
    $New | ForEach-Object { Write-Host "  $_" }
    Write-Host ('Die Belegung benennen und mit ihrem Besitzer in Tests/Support/Atlas.Tests.FirstUse.pas eintragen ' +
        'oder an der Ursache beheben, statt den Test einmal ungemessen vorweg laufen zu lassen.') -ForegroundColor Red
}
if ($Gone.Count -gt 0) {
    Write-Host 'Aufwärm-Routinen der Baseline gibt es nicht mehr:' -ForegroundColor Red
    $Gone | ForEach-Object { Write-Host "  $_" }
    Write-Host 'Baseline senken: pwsh Tools/Check-TestWarmUps.ps1 -Update' -ForegroundColor Red
}
if ($LockWarmUps.Count -gt 0) {
    Write-Host 'TMonitor.Enter direkt gefolgt von TMonitor.Exit (Sperre von Hand vorgewärmt):' -ForegroundColor Red
    $LockWarmUps | ForEach-Object { Write-Host "  $_" }
    Write-Host ('Gemeinsame Sperren mit TAtlasSharedLock.New (Atlas.Text.Locked) anlegen; Einmal-Belegungen, die nur ' +
        'die Messung stören, in Tests/Support/Atlas.Tests.FirstUse.pas benennen.') -ForegroundColor Red
}
if ($New.Count -gt 0 -or $Gone.Count -gt 0 -or $LockWarmUps.Count -gt 0) {
    exit 1
}
Write-Host "$($Sorted.Count) Aufwärm-Routinen, keine neue; keine von Hand vorgewärmte Sperre." -ForegroundColor Green
exit 0
