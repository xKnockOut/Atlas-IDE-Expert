<#
.SYNOPSIS
    Prüft, dass jeder Dialog des Plugins in einem Test gebaut wird.

.DESCRIPTION
    Ein Dialog, dessen Konstruktor scheitert (Ereignis vor dem Aufbau, Steuerelement ohne Fenster), öffnet in der
    IDE einfach nicht; die Sicherung des Hauptthreads schreibt den Fehler nur ins Protokoll. Ein Test, der den
    Dialog einmal anlegt, ihm und allen Steuerelementen ein Fenster gibt und ihn wieder freigibt, macht den
    Testlauf stattdessen rot (Hilfe: Tests/Support/Atlas.Tests.DialogSmoke.pas, TAtlasDialogSmoke.Realize).

    Gesammelt werden alle Klassen unter Packages/Atlas.IDE.*/Source/, die direkt oder über Zwischenstufen von
    TAtlasDialog erben (auch TAtlasDesignerDialog, TAtlasAnswerDialog und Klassen im implementation-Teil).
    Eine Klasse gilt als gebaut, wenn eine Datei unter Tests/ "<Klasse>.Create…" aufruft (Create, CreateDialog,
    CreateFor …) oder eine ihrer Ableitungen so gebaut wird (abstrakte Zwischenstufen mit geschütztem
    Konstruktor). Kommentare zählen nicht.

    Jeder Dialog ohne Test ist ein Verstoß; eine Ausnahmeliste gibt es nicht. Ein Dialog, der sich ohne IDE
    nicht bauen lässt, weil sein Konstruktor die IDE fragt, bekommt die Antwort vom Aufrufer.

    Exit-Code 0: jeder Dialog wird gebaut, 1: mindestens einer nicht.

.EXAMPLE
    pwsh Tools/Check-DialogTests.ps1

.EXAMPLE
    pwsh Tools/Check-DialogTests.ps1 -SelfTest
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [switch] $SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DialogRoot = 'TAtlasDialog'

# Quelltext ohne Kommentare ({ … }, (* … *), // …); Zeichenketten bleiben.
function Remove-Comments([string] $Text) {
    return [regex]::Replace($Text, '(?s)\{.*?\}|\(\*.*?\*\)|//[^\r\n]*', ' ')
}

# Klasse → Vorfahr für jede Deklaration "TName = class(TVorfahr…)" in den Texten.
function Get-Classes([string[]] $Texts) {
    $Parents = @{}
    foreach ($Text in $Texts) {
        foreach ($Match in [regex]::Matches((Remove-Comments $Text), '(?m)^\s*(T\w+)\s*=\s*class\s*\(\s*(T\w+)')) {
            $Parents[$Match.Groups[1].Value] = $Match.Groups[2].Value
        }
    }
    return $Parents
}

# Alle Nachfahren von $DialogRoot (ohne die Wurzel selbst), sortiert.
function Get-Dialogs([hashtable] $Parents) {
    $Dialogs = [Collections.Generic.HashSet[string]]::new()
    $Changed = $true
    while ($Changed) {
        $Changed = $false
        foreach ($Class in $Parents.Keys) {
            $Parent = $Parents[$Class]
            if (-not $Dialogs.Contains($Class) -and ($Parent -eq $DialogRoot -or $Dialogs.Contains($Parent))) {
                [void]$Dialogs.Add($Class)
                $Changed = $true
            }
        }
    }
    return @($Dialogs | Sort-Object -Culture 'en-US')
}

# Dialoge, die weder selbst noch über eine Ableitung in einem der Testtexte gebaut werden.
function Get-Untested([hashtable] $Parents, [string[]] $TestTexts) {
    $Tests = ($TestTexts | ForEach-Object { Remove-Comments $_ }) -join "`n"
    $Built = [Collections.Generic.HashSet[string]]::new()
    foreach ($Match in [regex]::Matches($Tests, '\b(T\w+)\s*\.\s*Create\w*\b')) {
        [void]$Built.Add($Match.Groups[1].Value)
    }
    $Dialogs = @(Get-Dialogs $Parents)
    # Eine gebaute Ableitung baut auch alle Vorfahren bis zur Wurzel.
    foreach ($Dialog in $Dialogs) {
        if (-not $Built.Contains($Dialog)) {
            continue
        }
        $Parent = $Parents[$Dialog]
        while ($Parent -and $Parent -ne $DialogRoot -and $Parents.ContainsKey($Parent)) {
            [void]$Built.Add($Parent)
            $Parent = $Parents[$Parent]
        }
    }
    return @($Dialogs | Where-Object { -not $Built.Contains($_) })
}

if ($SelfTest) {
    $Source = @(
        "type`n  TAtlasDialog = class(TForm)`n  end;`n  TEins = class(TAtlasDialog)`n  end;",
        "type`n  TBasis = class(TAtlasDialog)`n  end;`n  TZwei = class(TBasis)`n  end;`n  TFremd = class(TForm)`n  end;",
        "implementation`ntype`n  TInnen = class(TAtlasDialog)`n  end;`n  // TAlt = class(TAtlasDialog)"
    )
    $Parents = Get-Classes $Source
    $Cases = @(
        @{ Name = 'nichts gebaut'; Tests = @(''); Expected = 'TBasis,TEins,TInnen,TZwei' },
        @{ Name = 'Ableitung baut Vorfahren'; Tests = @("  m := TZwei.CreateFor(nil, 1);`n  n := TEins.Create(nil);");
            Expected = 'TInnen' },
        @{ Name = 'Kommentar zählt nicht'; Tests = @("// TInnen.Create(nil)`n{ TEins.CreateDialog }"); Expected = 'TBasis,TEins,TInnen,TZwei' },
        @{ Name = 'Vorfahr baut keine Ableitung'; Tests = @("TBasis.Create(nil); TEins.Create(nil); TInnen.Create(nil);");
            Expected = 'TZwei' }
    )
    $Failed = 0
    if ((@(Get-Dialogs $Parents) -join ',') -ne 'TBasis,TEins,TInnen,TZwei') {
        Write-Host "FEHLER: Dialoge: $(@(Get-Dialogs $Parents) -join ',')"
        $Failed++
    }
    foreach ($Case in $Cases) {
        $Got = @(Get-Untested $Parents $Case.Tests) -join ','
        if ($Got -ne $Case.Expected) {
            Write-Host "FEHLER: $($Case.Name): '$Got' statt '$($Case.Expected)'"
            $Failed++
        }
    }
    if ($Failed -gt 0) {
        exit 1
    }
    Write-Host 'Selbsttest der Prüfung auf Rauchtests der Dialoge bestanden.' -ForegroundColor Green
    exit 0
}

$SourceFiles = @(Get-ChildItem -Path (Join-Path $Root 'Packages') -Directory -Filter 'Atlas.IDE.*' |
    ForEach-Object { Join-Path $_.FullName 'Source' } | Where-Object { Test-Path $_ } |
    ForEach-Object { Get-ChildItem -Path $_ -Recurse -File -Filter '*.pas' })
$TestFiles = @(Get-ChildItem -Path (Join-Path $Root 'Tests') -Recurse -File -Filter '*.pas' |
    Where-Object { $_.FullName -notmatch '[\\/](Output|__history)[\\/]' })
$Parents = Get-Classes @($SourceFiles | ForEach-Object { [IO.File]::ReadAllText($_.FullName) })
$Dialogs = @(Get-Dialogs $Parents)
$Untested = @(Get-Untested $Parents @($TestFiles | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }))

if ($Untested.Count -gt 0) {
    Write-Host "Dialoge ohne Test, der sie baut ($($Untested.Count) von $($Dialogs.Count)):" -ForegroundColor Red
    $Untested | ForEach-Object { Write-Host "  $_" }
    Write-Host ('Je Dialog einen Test, der ihn mit kleinster Eingabe anlegt, TAtlasDialogSmoke.Realize aufruft und ' +
        'freigibt (Tests/Support/Atlas.Tests.DialogSmoke.pas).') -ForegroundColor Red
    exit 1
}
Write-Host "Alle $($Dialogs.Count) Dialoge werden in Tests gebaut." -ForegroundColor Green
exit 0
