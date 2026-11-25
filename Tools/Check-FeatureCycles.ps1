<#
.SYNOPSIS
    Prüft, dass Features desselben Präfixes keinen Zyklus bilden und die Richtungen einhalten.

.DESCRIPTION
    Feature einer Unit ist das erste Namenssegment nach dem längsten Präfix
    (Atlas.Core.Lsp.Session: Präfix Atlas.Core, Feature Lsp). Gezählt wird
    jeder uses-Eintrag aller .pas-Dateien des Repositorys zwischen zwei
    Features desselben Präfixes, interface und implementation, auch auf
    Contract-Units. Einstellungen stehen in atlas.json bei der Regel
    architecture-feature-cycle (eine Liste für Skript und Server):

      - prefixes    Präfixe der Ausgabeartefakte
      - exclude     Globs auf Pfad oder Unit-Namen, deren Einträge nicht zählen
                    (Tests, Werkzeuge, Vorlagen)
      - known       bestehende Zyklen "Präfix: A, B" als schrumpfende Liste:
                    Ein Zyklus innerhalb eines Eintrags ist bekannt, ein Eintrag
                    ohne genau gleichen Zyklus ist ein Fehler (kürzen)
      - directions  "Präfix: A < B < C" (B und C dürfen A verwenden, nicht
                    umgekehrt) und "Präfix: A | B" (keine Kante zwischen A und B)
      - knownEdges  bekannte Kanten gegen eine Richtung "Quelle -> Ziel"
                    (Unit-Namen), schrumpfende Liste wie known

    Dieselbe Auswertung rechnet TFeatureCycles in
    Atlas.Common.Architecture.FeatureCycles; beide prüfen die Fallliste
    Tests/Data/Architecture/feature-cycles.json (-SelfTest).

    Exit-Code 0: keine Befunde, 1: mindestens ein Befund.

.PARAMETER SelfTest
    Prüft nur die Auswertung gegen Tests/Data/Architecture/feature-cycles.json.

.EXAMPLE
    pwsh Tools/Check-FeatureCycles.ps1

.EXAMPLE
    pwsh Tools/Check-FeatureCycles.ps1 -SelfTest
#>
[CmdletBinding()]
param(
    [string] $Root = '',
    [switch] $SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path $Root).Path.TrimEnd('\', '/')

$RuleId = 'architecture-feature-cycle'
$TextComparer = [StringComparer]::OrdinalIgnoreCase

function Sort-Texts([string[]] $Items) {
    # Wie SortTexts in Atlas.Common.Architecture.FeatureCycles: ohne Groß-/Kleinschreibung, bei Gleichstand ordinal.
    $list = [Collections.Generic.List[string]]::new()
    foreach ($item in $Items) { $list.Add($item) }
    $list.Sort([Comparison[string]] {
        param($left, $right)
        $result = [string]::Compare($left, $right, [StringComparison]::OrdinalIgnoreCase)
        if ($result -eq 0) { $result = [string]::CompareOrdinal($left, $right) }
        return $result
    })
    return , $list.ToArray()
}

function Test-Glob([string] $Pattern, [string] $Path) {
    # Wie MatchesGlob in Atlas.Common.Configuration.Contract: * ohne Trenner, ** über Ordner, ? ein Zeichen,
    # ohne Groß-/Kleinschreibung; ein Ordnername schließt alles darunter ein.
    $pattern = $Pattern -replace '\\', '/'
    $path = $Path -replace '\\', '/'
    if ($pattern.EndsWith('/')) { $pattern += '**' }
    $candidates = @($pattern)
    if ($pattern -notmatch '[*?]') { $candidates += "$pattern/**" }
    foreach ($candidate in $candidates) {
        $regex = '^'
        for ($i = 0; $i -lt $candidate.Length; $i++) {
            $char = $candidate[$i]
            if ($char -eq '*' -and $i + 1 -lt $candidate.Length -and $candidate[$i + 1] -eq '*') {
                # "**/" trifft auch keinen Ordner.
                if ($i + 2 -lt $candidate.Length -and $candidate[$i + 2] -eq '/') { $regex += '(?:.*/)?'; $i += 2 }
                else { $regex += '.*'; $i++ }
            }
            elseif ($char -eq '*') { $regex += '[^/]*' }
            elseif ($char -eq '?') { $regex += '[^/]' }
            else { $regex += [regex]::Escape([string] $char) }
        }
        if ($path -match "(?i)$regex`$") { return $true }
    }
    return $false
}

function Test-Excluded([string[]] $Patterns, [string] $Value) {
    if (-not $Value) { return $false }
    foreach ($pattern in $Patterns) {
        if (Test-Glob $pattern $Value) { return $true }
    }
    return $false
}

function Get-FeatureOf([string] $Name, [string[]] $Prefixes) {
    $best = ''
    foreach ($prefix in $Prefixes) {
        if ($prefix.Length -gt $best.Length -and $Name.Length -gt $prefix.Length + 1 -and
            $Name.StartsWith("$prefix.", [StringComparison]::OrdinalIgnoreCase)) { $best = $prefix }
    }
    if (-not $best) { return $null }
    $feature = $Name.Substring($best.Length + 1).Split('.')[0]
    if (-not $feature) { return $null }
    return [pscustomobject]@{ Prefix = $best; Feature = $feature }
}

function Split-Entry([string] $Entry, [char] $Separator) {
    $colon = $Entry.IndexOf(':')
    if ($colon -lt 0) { return $null }
    $prefix = $Entry.Substring(0, $colon).Trim()
    $parts = @($Entry.Substring($colon + 1).Split($Separator) | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (-not $prefix -or $parts.Count -lt 2) { return $null }
    return [pscustomobject]@{ Prefix = $prefix; Parts = $parts }
}

function Get-ComponentText([string] $Prefix, [string[]] $Features) {
    return "${Prefix}: " + ((Sort-Texts $Features) -join ', ')
}

function Get-StringList($Object, [string] $Name) {
    if ($null -eq $Object -or -not $Object.PSObject.Properties[$Name]) { return @() }
    return @($Object.$Name | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
}

function Invoke-FeatureCycles($Options, $Edges) {
    # Liefert Findings (Schlüssel wie TFeatureCycles.Findings) und Messages (Text je Befund für die Ausgabe).
    $prefixes = Get-StringList $Options 'prefixes'
    $exclude = Get-StringList $Options 'exclude'
    $findings = [Collections.Generic.List[string]]::new()
    $messages = @{}
    function Add-Finding([string] $Key, [string] $Message) {
        $findings.Add($Key)
        $messages[$Key] = $Message
    }

    # Richtungen: verbotene Paare "präfix:von>nach" -> Eintrag
    $forbidden = [Collections.Generic.Dictionary[string, string]]::new($TextComparer)
    foreach ($entry in Get-StringList $Options 'directions') {
        $ordered = $entry.Contains('<')
        $split = if ($ordered) { Split-Entry $entry '<' } else { Split-Entry $entry '|' }
        if ($null -eq $split -or ($ordered -and $entry.Contains('|'))) {
            Add-Finding "invalid $entry" "directions: '$entry' ist ungültig (Präfix: A < B oder Präfix: A | B)"
            continue
        }
        for ($from = 0; $from -lt $split.Parts.Count; $from++) {
            for ($to = 0; $to -lt $split.Parts.Count; $to++) {
                if ($from -lt $to -or ($from -gt $to -and -not $ordered)) {
                    $forbidden["$($split.Prefix):$($split.Parts[$from])>$($split.Parts[$to])"] = $entry
                }
            }
        }
    }
    $known = @()
    foreach ($entry in Get-StringList $Options 'known') {
        $split = Split-Entry $entry ','
        if ($null -eq $split) {
            Add-Finding "invalid $entry" "known: '$entry' ist ungültig (Präfix: A, B)"
            continue
        }
        $known += [pscustomobject]@{ Prefix = $split.Prefix; Features = $split.Parts; Text = (Get-ComponentText $split.Prefix $split.Parts); Exact = $false }
    }
    $knownEdges = [Collections.Generic.Dictionary[string, string]]::new($TextComparer)
    foreach ($entry in Get-StringList $Options 'knownEdges') {
        $arrow = $entry.IndexOf('->')
        if ($arrow -le 0 -or -not $entry.Substring($arrow + 2).Trim()) {
            Add-Finding "invalid $entry" "knownEdges: '$entry' ist ungültig (Quelle -> Ziel)"
            continue
        }
        $knownEdges["$($entry.Substring(0, $arrow).Trim())>$($entry.Substring($arrow + 2).Trim())"] = $entry
    }
    $usedEdges = [Collections.Generic.Dictionary[string, bool]]::new($TextComparer)

    # Feature-Graph
    $nodeIds = [Collections.Generic.Dictionary[string, int]]::new($TextComparer)
    $nodes = [Collections.Generic.List[object]]::new()
    $next = [Collections.Generic.List[object]]::new()
    $examples = @{}
    function Get-Node([string] $Prefix, [string] $Feature) {
        $key = "$Prefix.$Feature"
        $id = 0
        if ($nodeIds.TryGetValue($key, [ref] $id)) { return $id }
        $id = $nodes.Count
        $nodeIds[$key] = $id
        $nodes.Add([pscustomobject]@{ Prefix = $Prefix; Feature = $Feature })
        $next.Add([Collections.Generic.List[int]]::new())
        return $id
    }
    foreach ($edge in $Edges) {
        $source = Get-FeatureOf $edge.SourceUnit $prefixes
        $target = Get-FeatureOf $edge.TargetUnit $prefixes
        if ($null -eq $source -or $null -eq $target -or $source.Prefix -ne $target.Prefix -or
            $source.Feature -eq $target.Feature) { continue }
        if ((Test-Excluded $exclude $edge.SourcePath) -or (Test-Excluded $exclude $edge.TargetPath) -or
            (Test-Excluded $exclude $edge.SourceUnit) -or (Test-Excluded $exclude $edge.TargetUnit)) { continue }
        $edgeKey = "$($edge.SourceUnit)>$($edge.TargetUnit)"
        if ($usedEdges.ContainsKey($edgeKey)) { continue }
        $usedEdges[$edgeKey] = $false
        $from = Get-Node $source.Prefix $source.Feature
        $to = Get-Node $target.Prefix $target.Feature
        if (-not $next[$from].Contains($to)) { $next[$from].Add($to) }
        $pairKey = "$from>$to"
        if (-not $examples.ContainsKey($pairKey)) { $examples[$pairKey] = "$($edge.SourceUnit) -> $($edge.TargetUnit)" }
        $entry = $null
        if ($forbidden.TryGetValue("$($source.Prefix):$($source.Feature)>$($target.Feature)", [ref] $entry)) {
            if ($knownEdges.ContainsKey($edgeKey)) { $usedEdges[$edgeKey] = $true }
            else {
                $where = if ($edge.PSObject.Properties['Where'] -and $edge.Where) { "$($edge.Where): " } else { '' }
                Add-Finding "direction $($edge.SourceUnit) -> $($edge.TargetUnit)" "${where}uses $($edge.TargetUnit) – $($edge.SourceUnit) läuft gegen die Richtung '$entry'"
            }
        }
    }

    # Tarjan, Komponenten mit mehr als einem Feature
    $script:fcIndex = 0
    $number = @{}; $low = @{}; $onStack = @{}
    $stack = [Collections.Generic.Stack[int]]::new()
    $components = [Collections.Generic.List[object]]::new()
    function Invoke-Visit([int] $Node) {
        $number[$Node] = $script:fcIndex; $low[$Node] = $script:fcIndex; $script:fcIndex++
        $stack.Push($Node); $onStack[$Node] = $true
        foreach ($nextNode in $next[$Node]) {
            if (-not $number.ContainsKey($nextNode)) {
                Invoke-Visit $nextNode
                $low[$Node] = [Math]::Min($low[$Node], $low[$nextNode])
            }
            elseif ($onStack[$nextNode]) { $low[$Node] = [Math]::Min($low[$Node], $number[$nextNode]) }
        }
        if ($low[$Node] -eq $number[$Node]) {
            $members = @()
            do { $member = $stack.Pop(); $onStack[$member] = $false; $members += $member } while ($member -ne $Node)
            if ($members.Count -gt 1) { $components.Add($members) }
        }
    }
    for ($node = 0; $node -lt $nodes.Count; $node++) {
        if (-not $number.ContainsKey($node)) { Invoke-Visit $node }
    }
    foreach ($members in $components) {
        $prefix = $nodes[$members[0]].Prefix
        $features = @($members | ForEach-Object { $nodes[$_].Feature })
        $covered = $false
        foreach ($item in $known) {
            if ($item.Prefix -ne $prefix) { continue }
            $inside = @($features | Where-Object { $item.Features -notcontains $_ }).Count -eq 0
            if ($inside) {
                $covered = $true
                if ($features.Count -eq $item.Features.Count) { $item.Exact = $true }
            }
        }
        if ($covered) { continue }
        $text = Get-ComponentText $prefix $features
        $sample = @()
        foreach ($from in $members) {
            foreach ($to in $next[$from]) {
                if ($members -contains $to) { $sample += $examples["$from>$to"] }
            }
        }
        Add-Finding "cycle $text" "Feature-Zyklus $text – $((Sort-Texts $sample) -join '; ')"
    }
    foreach ($item in $known) {
        if (-not $item.Exact) {
            Add-Finding "stale $($item.Text)" "atlas.json ${RuleId}: known '$($item.Text)' ist veraltet (der Zyklus ist kleiner geworden oder aufgelöst); Eintrag kürzen oder entfernen"
        }
    }
    foreach ($key in $knownEdges.Keys) {
        if ($usedEdges.ContainsKey($key) -and $usedEdges[$key]) { continue }
        $entry = $knownEdges[$key]
        $arrow = $entry.IndexOf('->')
        $label = "$($entry.Substring(0, $arrow).Trim()) -> $($entry.Substring($arrow + 2).Trim())"
        Add-Finding "staleEdge $label" "atlas.json ${RuleId}: knownEdges '$label' kommt nicht mehr vor; Eintrag entfernen"
    }
    return [pscustomobject]@{ Findings = (Sort-Texts $findings.ToArray()); Messages = $messages }
}

if ($SelfTest) {
    $data = Get-Content -Raw -Encoding UTF8 (Join-Path $Root 'Tests/Data/Architecture/feature-cycles.json') | ConvertFrom-Json
    $failures = @()
    foreach ($case in $data.cases) {
        $paths = if ($case.PSObject.Properties['paths']) { $case.paths } else { $null }
        $edges = foreach ($entry in @($case.edges)) {
            $arrow = $entry.IndexOf('->')
            $source = $entry.Substring(0, $arrow).Trim()
            $target = $entry.Substring($arrow + 2).Trim()
            $sourcePath = "Source/$source.pas"
            $targetPath = "Source/$target.pas"
            if ($null -ne $paths -and $paths.PSObject.Properties[$source]) { $sourcePath = $paths.$source }
            if ($null -ne $paths -and $paths.PSObject.Properties[$target]) { $targetPath = $paths.$target }
            [pscustomobject]@{ SourceUnit = $source; SourcePath = $sourcePath; TargetUnit = $target; TargetPath = $targetPath }
        }
        $result = Invoke-FeatureCycles $case.options @($edges)
        $expected = @($case.findings) -join ' | '
        $actual = @($result.Findings) -join ' | '
        if ($expected -cne $actual) { $failures += "$($case.name): erwartet '$expected', erhalten '$actual'" }
    }
    if ($failures.Count -gt 0) {
        Write-Host 'Feature-Zyklen weichen von der Fallliste ab:' -ForegroundColor Red
        $failures | ForEach-Object { Write-Host "  $_" }
        exit 1
    }
    Write-Host "Feature-Zyklen: $(@($data.cases).Count) Fälle wie erwartet." -ForegroundColor Green
    exit 0
}

function Remove-PascalNoise([string] $Text) {
    # Kommentare, Direktiven und Strings durch Leerzeichen ersetzen, Zeilenumbrüche behalten.
    $pattern = '(?s)\{.*?\}|\(\*.*?\*\)|//[^\r\n]*|''(?:[^'']|'''')*'''
    return [regex]::Replace($Text, $pattern, { param($m) [regex]::Replace($m.Value, '[^\r\n]', ' ') })
}

$config = Get-Content -Raw -Encoding UTF8 (Join-Path $Root 'atlas.json') | ConvertFrom-Json
$ruleProperty = $config.rules.PSObject.Properties[$RuleId]
if ($null -eq $ruleProperty -or $ruleProperty.Value -is [string]) {
    Write-Host "atlas.json hat keine Optionen für $RuleId." -ForegroundColor Red
    exit 1
}
$options = $ruleProperty.Value

# Alle Units des Repositorys; bei gleichem Namen gilt die unter Packages.
$files = @(Get-ChildItem -Path $Root -Recurse -File -Filter '*.pas' |
    Where-Object { $_.FullName.Substring($Root.Length + 1) -notmatch '^(Output|\.git)[\\/]' } |
    Sort-Object @{ Expression = { $_.FullName.Substring($Root.Length + 1) -notmatch '^Packages[\\/]' } }, FullName)
$units = [Collections.Generic.Dictionary[string, object]]::new($TextComparer)
foreach ($file in $files) {
    $name = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    if (-not $units.ContainsKey($name)) {
        $units[$name] = [pscustomobject]@{ Name = $name; File = $file.FullName; Path = ($file.FullName.Substring($Root.Length + 1) -replace '\\', '/') }
    }
}
$prefixes = Get-StringList $options 'prefixes'
$edges = [Collections.Generic.List[object]]::new()
foreach ($unit in $units.Values) {
    if ($null -eq (Get-FeatureOf $unit.Name $prefixes)) { continue }
    $text = Remove-PascalNoise ([IO.File]::ReadAllText($unit.File))
    foreach ($clause in [regex]::Matches($text, '(?is)\buses\b(.*?);')) {
        $offset = $clause.Groups[1].Index
        foreach ($entry in [regex]::Matches($clause.Groups[1].Value, '[A-Za-z_][A-Za-z0-9_.]*(?:\s+in\b)?')) {
            $name = ($entry.Value -replace '\s+in$', '').Trim()
            $target = $null
            if ($name -ieq 'in' -or -not $units.TryGetValue($name, [ref] $target)) { continue }
            $line = ($text.Substring(0, $offset + $entry.Index) -split "`n").Count
            $edges.Add([pscustomobject]@{ SourceUnit = $unit.Name; SourcePath = $unit.Path; TargetUnit = $target.Name
                TargetPath = $target.Path; Where = "$($unit.Path):$line" })
        }
    }
}
$result = Invoke-FeatureCycles $options $edges.ToArray()
$knownCount = @(Get-StringList $options 'known').Count
$knownEdgeCount = @(Get-StringList $options 'knownEdges').Count
if (@($result.Findings).Count -gt 0) {
    Write-Host "Feature-Zyklen und Richtungen: $(@($result.Findings).Count) Befunde" -ForegroundColor Red
    foreach ($key in $result.Findings) { Write-Host "  $($result.Messages[$key])" }
    exit 1
}
Write-Host "Feature-Zyklen und Richtungen: keine Befunde ($($edges.Count) uses-Einträge, bekannte Zyklen: $knownCount, bekannte Kanten gegen eine Richtung: $knownEdgeCount)." -ForegroundColor Green
exit 0
