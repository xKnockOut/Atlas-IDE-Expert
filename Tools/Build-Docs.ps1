<#
.SYNOPSIS
    Erzeugt die lokale HTML-Doku für die Installation (#766): Ordner Doku mit index.html und je einer Seite.

.DESCRIPTION
    Der Knopf „Atlas-Doku“ auf der Willkommensseite öffnet <Installationsordner>\Doku\index.html im Browser.
    Das Skript wandelt die Nutzer-Doku (README_DE.md, docs/Installation.md, docs/RAD-Studio.md,
    docs/Einstellungen.md, docs/Konfiguration.md, docs/Regeln.md, docs/Schluesselwoerter.md, docs/MCP.md und
    CHANGELOG.md) mit ConvertFrom-Markdown (Markdig, in PowerShell 7 enthalten) in eigenständige HTML-Seiten
    ohne externe Dateien (Stil eingebettet, hell und dunkel). Verweise auf andere Seiten der Doku zeigen auf die
    lokale Seite (mit Anker), Verweise auf andere Dateien des Repositorys auf GitHub; Webadressen bleiben.
    Der Ordner ist flach (der Installer kopiert nur Dateien eines Ordners).

    Ein Verweis auf eine lokale .html-Datei, die es nicht gibt, ist ein Fehler (Exit-Code 1).

.PARAMETER OutDir
    Zielordner; wird vorher geleert.

.EXAMPLE
    pwsh Tools/Build-Docs.ps1 -OutDir dist/Doku
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $OutDir,
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoUrl = 'https://github.com/xKnockOut/Atlas-IDE-Expert'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

# Quelle (relativ zum Repository) → Seite im Ordner Doku, Titel im Inhaltsverzeichnis und eine Zeile dazu.
$Pages = @(
    @{ Source = 'README_DE.md'; Target = 'Ueberblick.html'; Title = 'Überblick'; Text = 'Was Atlas kann und wie es aufgebaut ist.' },
    @{ Source = 'docs/Installation.md'; Target = 'Installation.html'; Title = 'Installation'; Text = 'Release-Paket, Aktualisierung und Deinstallation.' },
    @{ Source = 'docs/RAD-Studio.md'; Target = 'RAD-Studio.html'; Title = 'Atlas in RAD Studio'; Text = 'Alle Funktionen des Plugins in der IDE.' },
    @{ Source = 'docs/Einstellungen.md'; Target = 'Einstellungen.html'; Title = 'Einstellungen'; Text = 'Jede Einstellung mit Seite, Vorgabe und Ort.' },
    @{ Source = 'docs/Konfiguration.md'; Target = 'Konfiguration.html'; Title = 'Konfiguration (atlas.json)'; Text = 'Alle Schlüssel der Projektkonfiguration.' },
    @{ Source = 'docs/Regeln.md'; Target = 'Regeln.html'; Title = 'Prüfregeln'; Text = 'Alle Regeln der Code-Prüfung mit Beispielen.' },
    @{ Source = 'docs/Schluesselwoerter.md'; Target = 'Schluesselwoerter.html'; Title = 'Schlüsselwörter'; Text = 'Kurzhilfe zu Schlüsselwörtern und Direktiven.' },
    @{ Source = 'docs/MCP.md'; Target = 'MCP.html'; Title = 'MCP-Server'; Text = 'Atlas als Werkzeug für KI-Assistenten.' },
    @{ Source = 'CHANGELOG.md'; Target = 'Aenderungen.html'; Title = 'Änderungen'; Text = 'Was sich in welcher Version geändert hat.' }
)

$Version = 'unbekannt'
$VersionUnit = Join-Path $Root 'Packages/Atlas.Text/Source/Product/Atlas.Text.Product.Version.pas'
if (Test-Path $VersionUnit) {
    $Match = [regex]::Match([IO.File]::ReadAllText($VersionUnit), "Version = '([^']+)'")
    if ($Match.Success) { $Version = $Match.Groups[1].Value }
}

$ByPath = @{}
foreach ($Page in $Pages) { $ByPath[$Page.Source.ToLowerInvariant()] = $Page.Target }

function Escape-Html([string] $Text) {
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

# Pfad relativ zum Repository auflösen („docs/../README_DE.md“ → „README_DE.md“); $null außerhalb.
function Resolve-RepoPath([string] $BaseDir, [string] $Relative) {
    $Parts = New-Object System.Collections.Generic.List[string]
    $Joined = if ($BaseDir) { "$BaseDir/$Relative" } else { $Relative }
    foreach ($Part in ($Joined -replace '\\', '/').Split('/')) {
        if ($Part -eq '' -or $Part -eq '.') { continue }
        if ($Part -eq '..') {
            if ($Parts.Count -eq 0) { return $null }
            $Parts.RemoveAt($Parts.Count - 1)
            continue
        }
        $Parts.Add($Part)
    }
    return ($Parts -join '/')
}

function Convert-Link([string] $Href, [string] $BaseDir) {
    if ($Href -match '^(https?:|mailto:|#)') { return $Href }
    $Anchor = ''
    $Path = $Href
    $Hash = $Href.IndexOf('#')
    if ($Hash -ge 0) {
        $Anchor = $Href.Substring($Hash)
        $Path = $Href.Substring(0, $Hash)
    }
    $Path = [System.Uri]::UnescapeDataString($Path)
    $Resolved = Resolve-RepoPath $BaseDir $Path
    if ($null -eq $Resolved) { return $RepoUrl }
    $Key = $Resolved.ToLowerInvariant()
    if ($ByPath.ContainsKey($Key)) { return $ByPath[$Key] + $Anchor }
    return "$RepoUrl/blob/main/$Resolved$Anchor"
}

$Style = @'
:root { --bg: #ffffff; --fg: #1c2340; --muted: #5a6180; --line: #d5d9e4; --accent: #c45a1c; --code: #f3f4f8; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #15182a; --fg: #e8ebf4; --muted: #a3a9c2; --line: #30365a; --accent: #f29a4a; --code: #1f2338; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 15px/1.55 "Segoe UI", system-ui, sans-serif; }
header { border-bottom: 1px solid var(--line); padding: 10px 16px; display: flex; flex-wrap: wrap; gap: 6px 14px; align-items: baseline; }
header b { font-size: 16px; margin-right: 8px; }
header a { color: var(--muted); text-decoration: none; font-size: 13px; }
header a:hover, header a.on { color: var(--accent); }
main { max-width: 980px; margin: 0 auto; padding: 16px 16px 48px; overflow-wrap: anywhere; }
a { color: var(--accent); }
h1, h2, h3 { line-height: 1.25; }
code, pre { font-family: Consolas, "Cascadia Mono", monospace; font-size: 13px; background: var(--code); border-radius: 4px; }
code { padding: 1px 4px; }
pre { padding: 10px 12px; overflow-x: auto; }
pre code { padding: 0; background: none; }
table { border-collapse: collapse; display: block; overflow-x: auto; margin: 12px 0; }
th, td { border: 1px solid var(--line); padding: 5px 8px; text-align: left; vertical-align: top; font-size: 13px; }
th { background: var(--code); }
blockquote { margin: 0; padding: 0 12px; border-left: 3px solid var(--line); color: var(--muted); }
footer { max-width: 980px; margin: 0 auto; padding: 0 16px 24px; color: var(--muted); font-size: 12px; }
ul.pages { list-style: none; padding: 0; }
ul.pages li { padding: 8px 0; border-bottom: 1px solid var(--line); }
ul.pages small { display: block; color: var(--muted); }
'@

# Markdig bricht bei großen Tabellen mit „too deeply nested“ ab (Einstellungen.md, Konfiguration.md): Tabellen
# mit mehr als $TableRows Zeilen werden in mehrere Tabellen mit demselben Kopf geteilt.
$TableRows = 20
function Split-Tables([string] $Markdown) {
    $Lines = $Markdown.Replace("`r`n", "`n").Split("`n")
    $Out = New-Object System.Collections.Generic.List[string]
    $Index = 0
    while ($Index -lt $Lines.Count) {
        $Line = $Lines[$Index]
        $IsHeader = $Line.StartsWith('|') -and ($Index + 1 -lt $Lines.Count) -and ($Lines[$Index + 1] -match '^\|[-: |]+\|\s*$')
        if (-not $IsHeader) {
            $Out.Add($Line)
            $Index++
            continue
        }
        $Header = @($Line, $Lines[$Index + 1])
        $Out.AddRange([string[]]$Header)
        $Index += 2
        $Count = 0
        while ($Index -lt $Lines.Count -and $Lines[$Index].StartsWith('|')) {
            if ($Count -eq $TableRows) {
                $Out.Add('')
                $Out.AddRange([string[]]$Header)
                $Count = 0
            }
            $Out.Add($Lines[$Index])
            $Count++
            $Index++
        }
    }
    return ($Out -join "`n")
}

function Write-Page([string] $Target, [string] $Title, [string] $Body) {
    $Nav = New-Object System.Text.StringBuilder
    $Class = if ($Target -eq 'index.html') { ' class="on"' } else { '' }
    [void]$Nav.Append("<b>Atlas-Doku</b><a href=""index.html""$Class>Inhalt</a>")
    foreach ($Page in $Pages) {
        $Class = if ($Page.Target -eq $Target) { ' class="on"' } else { '' }
        [void]$Nav.Append("<a href=""$($Page.Target)""$Class>$(Escape-Html $Page.Title)</a>")
    }
    $Html = @"
<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$(Escape-Html $Title) – Atlas-Doku</title>
<style>
$Style
</style>
</head>
<body>
<header>$($Nav.ToString())</header>
<main>
$Body
</main>
<footer>Atlas $(Escape-Html $Version) · mit Atlas installierte Doku · aktuelle Fassung: <a href="$RepoUrl/tree/main/docs">$RepoUrl</a></footer>
</body>
</html>
"@
    [IO.File]::WriteAllText((Join-Path $OutDir $Target), $Html.Replace("`r`n", "`n"), $Utf8)
}

if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path

foreach ($Page in $Pages) {
    $SourcePath = Join-Path $Root $Page.Source
    if (-not (Test-Path $SourcePath)) { throw "Quelle fehlt: $($Page.Source)" }
    $Markdown = [IO.File]::ReadAllText($SourcePath).TrimStart([char]0xFEFF)
    $Html = (ConvertFrom-Markdown -InputObject (Split-Tables $Markdown)).Html
    $BaseDir = Split-Path -Parent $Page.Source
    $BaseDir = $BaseDir -replace '\\', '/'
    $Html = [regex]::Replace($Html, '(href|src)="([^"]*)"', {
            param($M)
            $Value = [System.Net.WebUtility]::HtmlDecode($M.Groups[2].Value)
            return $M.Groups[1].Value + '="' + (Escape-Html (Convert-Link $Value $BaseDir)) + '"'
        })
    Write-Page $Page.Target $Page.Title $Html
}

$List = New-Object System.Text.StringBuilder
[void]$List.Append("<h1>Atlas-Doku</h1>`n<p>Die mit Atlas $(Escape-Html $Version) installierte Doku. Die aktuelle Fassung steht im <a href=""$RepoUrl/tree/main/docs"">Repository</a>.</p>`n<ul class=""pages"">`n")
foreach ($Page in $Pages) {
    [void]$List.Append("<li><a href=""$($Page.Target)"">$(Escape-Html $Page.Title)</a><small>$(Escape-Html $Page.Text)</small></li>`n")
}
[void]$List.Append('</ul>')
Write-Page 'index.html' 'Inhalt' $List.ToString()

# Wächter: Jeder lokale Verweis zeigt auf eine erzeugte Seite.
$Problems = New-Object System.Collections.Generic.List[string]
$Written = @(Get-ChildItem $OutDir -File | ForEach-Object { $_.Name })
foreach ($File in $Written) {
    $Text = [IO.File]::ReadAllText((Join-Path $OutDir $File))
    foreach ($M in [regex]::Matches($Text, 'href="([^"#:]+\.html)(#[^"]*)?"')) {
        if ($Written -notcontains $M.Groups[1].Value) { $Problems.Add("${File}: Verweis auf fehlende Seite $($M.Groups[1].Value)") }
    }
}
if ($Problems.Count -gt 0) {
    $Problems | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}
Write-Host "Atlas-Doku: $($Written.Count) Seiten in $OutDir"
